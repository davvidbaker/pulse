defmodule Pulse.Logs do
  @moduledoc """
  The Logs context. Owns UsageLog.
  Handles creating usage logs and triggering async calculation.
  """

  import Ecto.Query
  alias Pulse.Repo
  alias Pulse.Logs.UsageLog

  @spec log_usage(binary(), map()) :: {:ok, UsageLog.t()} | {:error, Ecto.Changeset.t()}
  def log_usage(user_id, attrs) do
    attrs = Map.put(attrs, "user_id", user_id)

    with {:ok, log} <-
           %UsageLog{}
           |> UsageLog.changeset(attrs)
           |> Repo.insert() do
      Oban.insert(Pulse.Workers.CalculationWorker.new(%{log_id: log.id}))
      {:ok, log}
    end
  end

  @spec list_logs(binary(), map()) :: [UsageLog.t()]
  def list_logs(user_id, opts \\ %{}) do
    base_query =
      UsageLog
      |> where([l], l.user_id == ^user_id)
      |> order_by([l], desc: l.logged_at)
      |> preload(:energy_source)

    base_query
    |> maybe_filter_date(opts)
    |> maybe_filter_source(opts)
    |> maybe_paginate(opts)
    |> Repo.all()
  end

  @spec get_log!(binary()) :: UsageLog.t()
  def get_log!(id), do: Repo.get!(UsageLog, id) |> Repo.preload(:energy_source)

  @spec get_log(binary(), binary()) :: UsageLog.t() | nil
  def get_log(user_id, id) do
    UsageLog
    |> where([l], l.id == ^id and l.user_id == ^user_id)
    |> preload(:energy_source)
    |> Repo.one()
  end

  @spec update_log(UsageLog.t(), map()) :: {:ok, UsageLog.t()} | {:error, Ecto.Changeset.t()}
  def update_log(%UsageLog{} = log, attrs) do
    with {:ok, updated} <-
           log
           |> UsageLog.changeset(attrs)
           |> Repo.update() do
      Oban.insert(Pulse.Workers.CalculationWorker.new(%{log_id: updated.id}))
      {:ok, updated}
    end
  end

  @spec delete_log(UsageLog.t()) :: {:ok, UsageLog.t()} | {:error, Ecto.Changeset.t()}
  def delete_log(%UsageLog{} = log), do: Repo.delete(log)

  @spec update_computed_fields(UsageLog.t(), map()) ::
          {:ok, UsageLog.t()} | {:error, Ecto.Changeset.t()}
  def update_computed_fields(%UsageLog{} = log, result) do
    log
    |> UsageLog.computed_changeset(result)
    |> Repo.update()
  end

  @spec recalculate_log(binary()) :: {:ok, UsageLog.t()} | {:error, term()}
  def recalculate_log(log_id) do
    log = get_log!(log_id) |> Repo.preload(:energy_source)
    source = log.energy_source

    log_input = %{
      duration_minutes: log.duration_minutes,
      quantity: log.quantity && Decimal.to_float(log.quantity),
      logged_at: log.logged_at,
      input_type: log.input_type
    }

    case Pulse.Engine.calculate(log_input, source) do
      {:ok, result} -> update_computed_fields(log, result)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec new_log_changeset(map()) :: Ecto.Changeset.t()
  def new_log_changeset(attrs \\ %{}) do
    UsageLog.changeset(%UsageLog{}, attrs)
  end

  @spec recent_computed_logs(binary(), pos_integer()) :: [UsageLog.t()]
  def recent_computed_logs(user_id, days \\ 14) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    UsageLog
    |> where(
      [l],
      l.user_id == ^user_id and l.logged_at >= ^cutoff and not is_nil(l.computed_cost)
    )
    |> order_by([l], desc: l.logged_at)
    |> Repo.all()
  end

  defp maybe_filter_date(query, %{"from" => from, "to" => to})
       when not is_nil(from) and not is_nil(to) do
    where(query, [l], l.logged_at >= ^from and l.logged_at <= ^to)
  end

  defp maybe_filter_date(query, _), do: query

  defp maybe_filter_source(query, %{"energy_source_id" => source_id})
       when not is_nil(source_id) do
    where(query, [l], l.energy_source_id == ^source_id)
  end

  defp maybe_filter_source(query, _), do: query

  defp maybe_paginate(query, %{"page" => page, "per_page" => per_page})
       when is_integer(page) and is_integer(per_page) do
    offset = (page - 1) * per_page
    query |> limit(^per_page) |> offset(^offset)
  end

  defp maybe_paginate(query, _), do: limit(query, 50)
end
