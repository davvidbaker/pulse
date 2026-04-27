defmodule Pulse.Workers.SuggestionWorker do
  @moduledoc """
  Oban cron worker that regenerates suggestions for all users daily at 02:00 UTC.
  """

  use Oban.Worker, queue: :suggestions, max_attempts: 3

  import Ecto.Query
  alias Pulse.{Repo, Suggestions}
  alias Pulse.Accounts.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    Suggestions.generate_suggestions(user_id)
    :ok
  end

  def perform(%Oban.Job{}) do
    User
    |> select([u], u.id)
    |> Repo.all()
    |> Enum.each(fn user_id ->
      Suggestions.generate_suggestions(user_id)
    end)

    :ok
  end
end
