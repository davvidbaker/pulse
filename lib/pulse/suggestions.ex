defmodule Pulse.Suggestions do
  @moduledoc """
  The Suggestions context. Owns Suggestion.
  Generates and stores personalized energy-saving tips.
  """

  import Ecto.Query
  alias Pulse.Repo
  alias Pulse.Suggestions.Suggestion
  alias Pulse.Logs.UsageLog
  alias Pulse.Setup

  @min_weekly_saving_threshold 0.10

  @spec list_active_suggestions(binary()) :: [Suggestion.t()]
  def list_active_suggestions(user_id) do
    Suggestion
    |> where([s], s.user_id == ^user_id and is_nil(s.dismissed_at))
    |> order_by([s], desc: s.estimated_saving_weekly)
    |> preload(:energy_source)
    |> Repo.all()
  end

  @spec dismiss_suggestion(binary(), binary()) :: {:ok, Suggestion.t()} | {:error, term()}
  def dismiss_suggestion(user_id, suggestion_id) do
    case Repo.get_by(Suggestion, id: suggestion_id, user_id: user_id) do
      nil -> {:error, :not_found}
      suggestion ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        suggestion |> Suggestion.changeset(%{dismissed_at: now}) |> Repo.update()
    end
  end

  @spec act_on_suggestion(binary(), binary()) :: {:ok, Suggestion.t()} | {:error, term()}
  def act_on_suggestion(user_id, suggestion_id) do
    case Repo.get_by(Suggestion, id: suggestion_id, user_id: user_id) do
      nil -> {:error, :not_found}
      suggestion ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        suggestion |> Suggestion.changeset(%{acted_on_at: now}) |> Repo.update()
    end
  end

  @doc """
  Generates and upserts suggestions for a user based on the last 14 days of logs.
  Should be called after calculation completes and on a nightly schedule.
  """
  @spec generate_suggestions(binary()) :: :ok
  def generate_suggestions(user_id) do
    sources = Setup.list_energy_sources(user_id)
    Enum.each(sources, fn source -> generate_for_source(user_id, source) end)
    :ok
  end

  defp generate_for_source(user_id, %{source_type: "electricity"} = source) do
    peak_hours = get_in(source.metadata, ["peak_hours"])

    if peak_hours && peak_hours != [] do
      generate_time_shift_suggestion(user_id, source, peak_hours)
    end

    generate_reduce_duration_suggestion(user_id, source)
  end

  defp generate_for_source(user_id, source) do
    generate_reduce_duration_suggestion(user_id, source)
  end

  defp generate_time_shift_suggestion(user_id, source, peak_hours) do
    cutoff = DateTime.add(DateTime.utc_now(), -14, :day)

    peak_logs =
      UsageLog
      |> where(
        [l],
        l.user_id == ^user_id and
          l.energy_source_id == ^source.id and
          l.logged_at >= ^cutoff and
          not is_nil(l.computed_cost)
      )
      |> Repo.all()
      |> Enum.filter(fn log ->
        time = DateTime.to_time(log.logged_at)
        in_any_peak_window?(time, peak_hours)
      end)

    unless peak_logs == [] do
      total_peak_cost =
        Enum.reduce(peak_logs, Decimal.new(0), fn l, acc ->
          Decimal.add(acc, l.computed_cost || Decimal.new(0))
        end)

      # Off-peak cost = peak cost / peak multiplier (approximate savings)
      avg_multiplier =
        Enum.map(peak_hours, fn w -> w["multiplier"] || 1.0 end)
        |> Enum.sum()
        |> Kernel./(length(peak_hours))

      off_peak_cost = Decimal.div(total_peak_cost, Decimal.from_float(avg_multiplier))
      savings_14_days = Decimal.sub(total_peak_cost, off_peak_cost)
      weekly_savings = Decimal.div(Decimal.mult(savings_14_days, Decimal.new(7)), Decimal.new(14))

      if Decimal.gt?(weekly_savings, Decimal.from_float(@min_weekly_saving_threshold)) do
        upsert_suggestion(user_id, source.id, "time_shift", %{
          title: "Shift #{source.name} usage off-peak",
          body:
            "You could save approximately $#{Decimal.round(weekly_savings, 2)}/week by using #{source.name} during off-peak hours.",
          estimated_saving_weekly: weekly_savings
        })
      end
    end
  end

  defp generate_reduce_duration_suggestion(user_id, source) do
    reference_duration = get_in(source.metadata, ["reference_duration_minutes"])

    if reference_duration do
      cutoff = DateTime.add(DateTime.utc_now(), -14, :day)

      avg_duration =
        UsageLog
        |> where(
          [l],
          l.user_id == ^user_id and
            l.energy_source_id == ^source.id and
            l.logged_at >= ^cutoff and
            l.input_type == "duration" and
            not is_nil(l.duration_minutes)
        )
        |> select([l], avg(l.duration_minutes))
        |> Repo.one()

      if avg_duration && avg_duration > reference_duration * 1.2 do
        excess_pct = Float.round((avg_duration - reference_duration) / reference_duration * 100, 0)

        upsert_suggestion(user_id, source.id, "reduce_duration", %{
          title: "Reduce #{source.name} session length",
          body:
            "Your average #{source.name} session is #{trunc(excess_pct)}% longer than typical. Reducing by #{trunc(avg_duration - reference_duration)} min could lower your bills.",
          estimated_saving_weekly: Decimal.new(0)
        })
      end
    end
  end

  defp upsert_suggestion(user_id, source_id, type, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    existing =
      Repo.get_by(Suggestion,
        user_id: user_id,
        energy_source_id: source_id,
        suggestion_type: type
      )

    full_attrs =
      Map.merge(attrs, %{
        user_id: user_id,
        energy_source_id: source_id,
        suggestion_type: type,
        generated_at: now,
        dismissed_at: nil
      })

    case existing do
      nil ->
        Repo.insert(Suggestion.changeset(%Suggestion{}, full_attrs))

      suggestion ->
        Repo.update(Suggestion.changeset(suggestion, full_attrs))
    end
  end

  defp in_any_peak_window?(time, peak_hours) do
    Enum.any?(peak_hours, fn window ->
      with {:ok, from} <- parse_time(window["from"]),
           {:ok, to} <- parse_time(window["to"]) do
        in_time_window?(time, from, to)
      else
        _ -> false
      end
    end)
  end

  defp parse_time(str) when is_binary(str), do: Time.from_iso8601(str <> ":00")
  defp parse_time(_), do: :error

  defp in_time_window?(time, from, to) do
    if Time.compare(from, to) == :lt do
      Time.compare(time, from) != :lt and Time.compare(time, to) == :lt
    else
      Time.compare(time, from) != :lt or Time.compare(time, to) == :lt
    end
  end
end
