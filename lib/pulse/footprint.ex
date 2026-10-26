defmodule Pulse.Footprint do
  @moduledoc "Postgres boundary for Dagster inputs, daily results and publication receipts."
  import Ecto.Query
  alias Pulse.{Repo, Accounts.User}
  alias Pulse.Footprint.{Profile, Observation, Result}

  @scopes ~w(home_electricity home_heating ground_travel food remote_compute flights goods services)
  @kinds ~w(pulse_energy pulse_energy_lower pulse_energy_upper pulse_scope_coverage pulse_observed_fraction)
  def scopes, do: @scopes
  def kinds, do: @kinds

  def profile(user_id) do
    Repo.insert(%Profile{user_id: user_id}, on_conflict: :nothing, conflict_target: :user_id)
    Repo.get_by!(Profile, user_id: user_id)
  end

  def update_profile(user_id, attrs) do
    transaction(user_id, fn ->
      case Profile.changeset(profile(user_id), attrs) |> Repo.update() do
        {:ok, p} ->
          invalidate(user_id)
          p

        {:error, cs} ->
          Repo.rollback(cs)
      end
    end)
  end

  def list_observations(user_id) do
    Repo.all(
      from o in Observation,
        where: o.user_id == ^user_id,
        order_by: [desc: o.starts_on],
        limit: 100
    )
  end

  def put_observation(user_id, attrs) do
    transaction(user_id, fn ->
      external_id = attrs["external_id"] || Ecto.UUID.generate()
      existing = Repo.get_by(Observation, user_id: user_id, external_id: external_id)
      row = existing || %Observation{user_id: user_id}

      case Observation.changeset(row, Map.put(attrs, "external_id", external_id))
           |> Repo.insert_or_update() do
        {:ok, saved} ->
          invalidate(user_id)
          saved

        {:error, cs} ->
          Repo.rollback(cs)
      end
    end)
  end

  def delete_observation(user_id, id) do
    transaction(user_id, fn ->
      row = Repo.get_by(Observation, user_id: user_id, id: id) || Repo.rollback(:not_found)
      Repo.delete!(row)
      invalidate(user_id)
    end)
  end

  def invalidate(user_id) do
    Repo.update_all(from(r in Result, where: r.user_id == ^user_id), set: [dirty: true])
    :ok
  end

  def day_bounds(day, timezone) do
    first = DateTime.new!(day, ~T[00:00:00], timezone)
    last = DateTime.new!(Date.add(day, 1), ~T[00:00:00], timezone)
    {DateTime.shift_zone!(first, "Etc/UTC"), DateTime.shift_zone!(last, "Etc/UTC")}
  end

  def local_today(user), do: DateTime.now!(user.timezone) |> DateTime.to_date()

  def inputs(user, day) do
    p = profile(user.id)

    observations =
      Repo.all(
        from o in Observation,
          where: o.user_id == ^user.id and o.starts_on <= ^day and o.ends_on >= ^day,
          order_by: o.id
      )

    {first, last} = day_bounds(day, user.timezone)

    logs =
      Repo.all(
        from l in Pulse.Logs.UsageLog,
          where: l.user_id == ^user.id and l.logged_at >= ^first and l.logged_at < ^last,
          preload: :energy_source,
          order_by: l.id
      )

    history =
      Repo.all(
        from r in Result,
          where:
            r.user_id == ^user.id and r.date < ^day and r.date >= ^Date.add(day, -28) and
              not r.dirty,
          order_by: r.date
      )
      |> Enum.flat_map(fn r ->
        for {scope, data} <- r.data["categories"],
            data["complete_observed"] == true,
            do: %{
              "date" => Date.to_iso8601(r.date),
              "scope" => scope,
              "source_kwh" => data["source_kwh"],
              "complete_observed" => true
            }
      end)

    profile_data =
      p
      |> Map.from_struct()
      |> Map.take([
        :household_size,
        :grid_source_factor,
        :heating,
        :drives,
        :daily_travel_km,
        :vehicle_kwh_per_km,
        :vehicle_id,
        :vehicle_energy_basis,
        :baselines
      ])
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    snapshot = %{
      "date" => Date.to_iso8601(day),
      "timezone" => user.timezone,
      "profile" => profile_data,
      "history" => history,
      "observations" =>
        Enum.map(observations, &export_observation(&1, p)) ++
          Enum.flat_map(logs, &export_log(&1, p))
    }

    hash = :crypto.hash(:sha256, :erlang.term_to_binary(snapshot)) |> Base.encode16(case: :lower)
    Map.put(snapshot, "input_hash", hash)
  end

  defp export_observation(o, p) do
    days = Date.diff(o.ends_on, o.starts_on) + 1

    %{
      "id" => o.id,
      "scope" => o.scope,
      "quantity" => o.quantity / days,
      "unit" => o.unit,
      "basis" => o.basis,
      "factor_kwh_per_unit" => o.factor_kwh_per_unit,
      "coverage" => o.coverage,
      "allocation" => o.allocation / if(o.household, do: p.household_size, else: 1),
      "included_in_scope" => o.included_in_scope,
      "source_ref" => o.source_ref,
      "quality" => o.quality,
      "origin" => "observation",
      "fuel_type" => o.payload["fuel_type"],
      "payload" => o.payload
    }
  end

  defp export_log(l, p) do
    scope =
      case l.energy_source.source_type do
        "electricity" -> "home_electricity"
        "fuel" -> "ground_travel"
        type when type in ["gas", "heating"] -> "home_heating"
        _ -> nil
      end

    # Existing duration logs cover an activity, not a complete category/day.
    # Water's legacy zero energy is never treated as measured absence of service energy.
    if scope && l.computed_kwh && not (l.energy_source.metadata["fuel_type"] == "electric") do
      basis =
        case l.energy_source.source_type do
          "electricity" -> "electricity"
          type when type in ["gas", "heating"] -> "gas"
          _ -> "fuel"
        end

      [
        %{
          "id" => l.id,
          "scope" => scope,
          "quantity" => Decimal.to_float(l.computed_kwh),
          "unit" => "kwh",
          "basis" => basis,
          "coverage" => 0.0,
          "allocation" =>
            if(scope in ["home_electricity", "home_heating"], do: 1 / p.household_size, else: 1.0),
          "source_ref" => "legacy usage log",
          "quality" => "estimated",
          "origin" => "legacy_log"
        }
      ]
    else
      []
    end
  end

  def work_dates(user) do
    today = local_today(user)
    # Dirty historical days and unpublished results remain discoverable after outages.
    dates =
      Repo.all(
        from r in Result, where: r.user_id == ^user.id, select: {r.date, r.dirty, r.receipts}
      )

    pending =
      for {day, dirty, receipts} <- dates,
          dirty or not Enum.all?(@kinds, &Map.has_key?(receipts, &1)),
          do: day

    ranges =
      Repo.all(
        from o in Observation, where: o.user_id == ^user.id, select: {o.starts_on, o.ends_on}
      )

    known = MapSet.new(Enum.map(dates, &elem(&1, 0)))

    missing =
      Enum.flat_map(ranges, fn {a, b} ->
        Enum.reject(Date.range(a, b), &MapSet.member?(known, &1))
      end)

    legacy_dates =
      Repo.all(from l in Pulse.Logs.UsageLog, where: l.user_id == ^user.id, select: l.logged_at)
      |> Enum.map(&(DateTime.shift_zone!(&1, user.timezone) |> DateTime.to_date()))
      |> Enum.reject(&MapSet.member?(known, &1))

    historical =
      (pending ++ missing ++ legacy_dates)
      |> Enum.uniq()
      |> Enum.filter(
        &(Date.compare(&1, today) == :lt and Date.compare(&1, ~D[2020-01-01]) != :lt)
      )
      |> Enum.sort(Date)
      |> Enum.take(29)

    (historical ++ [Date.add(today, -1), today])
    |> Enum.uniq()
    |> Enum.sort(Date)
    |> Enum.map(&Date.to_iso8601/1)
  end

  def result(user_id, day), do: Repo.get_by(Result, user_id: user_id, date: day)

  def period_summary(user, period, today \\ nil) do
    today = today || local_today(user)
    {first, last} = Pulse.Footprint.PeriodSummary.bounds(today, period)

    results = results_in_range(user.id, first, last)
    Pulse.Footprint.PeriodSummary.new(results, period, first, last, user.timezone)
  end

  def results_in_range(user_id, first, last) do
    Repo.all(
      from r in Result,
        where: r.user_id == ^user_id and r.date >= ^first and r.date <= ^last,
        order_by: r.date
    )
  end

  def save_result(user, day, data) do
    transaction(user.id, fn ->
      unless valid_result?(data, day) and data["timezone"] == user.timezone,
        do: Repo.rollback(:invalid_result)

      unless inputs(user, day)["input_hash"] == data["input_hash"],
        do: Repo.rollback(:stale_inputs)

      old = result(user.id, day)

      if old && old.input_hash == data["input_hash"] &&
           old.methodology_version == data["methodology_version"] && old.data == data do
        old |> Ecto.Changeset.change(dirty: false) |> Repo.update!()
      else
        row = old || %Result{user_id: user.id, date: day, revision: 0}

        saved =
          row
          |> Ecto.Changeset.change(%{
            input_hash: data["input_hash"],
            methodology_version: data["methodology_version"],
            revision: row.revision + 1,
            data: data,
            receipts: %{},
            dirty: false,
            calculated_at: DateTime.utc_now()
          })
          |> Repo.insert_or_update!()

        # Re-evaluate descendants whose personal-history fallback can have changed.
        Repo.update_all(
          from(r in Result,
            where: r.user_id == ^user.id and r.date > ^day and r.date <= ^Date.add(day, 28)
          ),
          set: [dirty: true]
        )

        saved
      end
    end)
  end

  defp valid_result?(data, day) do
    numeric = ~w(total_kwh lower_kwh upper_kwh observed_fraction)
    categories = data["categories"]

    data["date"] == Date.to_iso8601(day) and data["energy_basis"] == "source_equivalent" and
      is_binary(data["methodology_version"]) and data["methodology_version"] != "" and
      data["status"] in ~w(partial estimated) and is_list(data["missing_scopes"]) and
      Enum.all?(data["missing_scopes"], &(&1 in @scopes)) and
      Enum.all?(numeric, fn k -> is_number(data[k]) and data[k] >= 0 end) and
      data["observed_fraction"] <= 1 and is_map(categories) and
      Enum.sort(Map.keys(categories)) == Enum.sort(@scopes) and
      Enum.all?(categories, fn {_, c} ->
        is_map(c) and is_number(c["source_kwh"]) and c["source_kwh"] >= 0 and
          is_boolean(c["missing"]) and is_boolean(c["complete_observed"]) and
          is_binary(c["method"]) and is_number(c["coverage"]) and c["coverage"] >= 0 and
          c["coverage"] <= 1
      end) and
      abs(Enum.sum(Enum.map(categories, fn {_, c} -> c["source_kwh"] end)) - data["total_kwh"]) <
        0.0001 and
      Enum.sort(data["missing_scopes"]) ==
        Enum.sort(for {scope, c} <- categories, c["missing"], do: scope) and
      data["status"] == if(data["missing_scopes"] == [], do: "estimated", else: "partial") and
      data["lower_kwh"] <= data["total_kwh"] and data["upper_kwh"] >= data["total_kwh"]
  end

  def receipt(user_id, day, revision, kind, observation_id) do
    transaction(user_id, fn ->
      row = result(user_id, day) || Repo.rollback(:not_found)
      unless row.revision == revision and not row.dirty, do: Repo.rollback(:stale_inputs)
      unless kind in @kinds and is_integer(observation_id), do: Repo.rollback(:invalid_receipt)

      row
      |> Ecto.Changeset.change(receipts: Map.put(row.receipts, kind, observation_id))
      |> Repo.update!()
    end)
  end

  def export_result(row) do
    Map.merge(row.data, %{
      "revision" => row.revision,
      "dirty" => row.dirty,
      "receipts" => row.receipts,
      "calculated_at" => DateTime.to_iso8601(row.calculated_at)
    })
  end

  def transaction(user_id, fun) do
    Repo.transaction(fn ->
      Repo.one!(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE")
      fun.()
    end)
  end
end
