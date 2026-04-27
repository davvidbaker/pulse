defmodule Pulse.DataCase do
  @moduledoc """
  Base case for tests that interact with the database.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Pulse.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Pulse.DataCase
    end
  end

  setup tags do
    Pulse.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Pulse.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
