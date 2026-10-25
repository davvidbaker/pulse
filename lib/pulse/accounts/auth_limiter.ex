defmodule Pulse.Accounts.AuthLimiter do
  @moduledoc "Sliding-window auth limits for this application node; identities are hashed in memory."
  use GenServer

  @policies %{login: {10, 300_000}, recovery: {3, 900_000}, register: {5, 900_000}}
  @global_limit 300

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  def allow?(action, email, server \\ __MODULE__) do
    identity =
      if is_binary(email) and byte_size(email) <= 320,
        do: Pulse.Accounts.User.normalize_email(email),
        else: "invalid"

    GenServer.call(server, {:allow, action, :crypto.hash(:sha256, identity)})
  end

  @impl true
  def init(opts) do
    Process.send_after(self(), :prune, 60_000)

    {:ok,
     %{
       attempts: %{},
       global: [],
       clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
     }}
  end

  @impl true
  def handle_call({:allow, action, identity}, _, state) do
    now = state.clock.()
    {limit, window} = Map.fetch!(@policies, action)
    key = {action, identity}
    global = Enum.filter(state.global, &(&1 > now - 60_000))
    attempts = Enum.filter(Map.get(state.attempts, key, []), &(&1 > now - window))
    allowed = length(global) < @global_limit and length(attempts) < limit
    # Count denied requests globally too, but keep every list bounded.
    global = Enum.take([now | global], @global_limit)
    entries = if allowed, do: Map.put(state.attempts, key, [now | attempts]), else: state.attempts
    {:reply, allowed, %{state | attempts: entries, global: global}}
  end

  @impl true
  def handle_info(:prune, state) do
    now = state.clock.()

    entries =
      Map.new(state.attempts, fn {{action, _} = key, times} ->
        {_, window} = Map.fetch!(@policies, action)
        {key, Enum.filter(times, &(&1 > now - window))}
      end)
      |> Map.reject(fn {_, times} -> times == [] end)

    Process.send_after(self(), :prune, 60_000)

    {:noreply,
     %{state | attempts: entries, global: Enum.filter(state.global, &(&1 > now - 60_000))}}
  end
end
