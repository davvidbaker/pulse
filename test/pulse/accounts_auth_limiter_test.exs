defmodule Pulse.Accounts.AuthLimiterTest do
  use ExUnit.Case, async: true
  alias Pulse.Accounts.AuthLimiter

  test "limits normalize addresses, separate identities and expire without sleeping" do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    server = start_supervised!({AuthLimiter, name: nil, clock: fn -> Agent.get(clock, & &1) end})
    for _ <- 1..10, do: assert(AuthLimiter.allow?(:login, " Person@example.com ", server))
    refute AuthLimiter.allow?(:login, "person@EXAMPLE.COM", server)
    assert AuthLimiter.allow?(:login, "other@example.com", server)
    Agent.update(clock, fn _ -> 300_001 end)
    assert AuthLimiter.allow?(:login, "person@example.com", server)
    for _ <- 1..3, do: assert(AuthLimiter.allow?(:recovery, "person@example.com", server))
    refute AuthLimiter.allow?(:recovery, "person@example.com", server)
  end

  test "global ceiling bounds attempts even when identities change" do
    server = start_supervised!({AuthLimiter, name: nil, clock: fn -> 0 end})
    for n <- 1..300, do: assert(AuthLimiter.allow?(:login, "person#{n}@example.com", server))
    refute AuthLimiter.allow?(:login, "fresh@example.com", server)
  end
end
