defmodule PulseWeb.Plugs.CanonicalHostTest do
  use ExUnit.Case, async: false
  import Plug.Test
  alias PulseWeb.Plugs.CanonicalHost

  setup do
    previous =
      for key <- [:canonical_host, :legacy_host], do: {key, Application.fetch_env(:pulse, key)}

    Application.put_env(:pulse, :canonical_host, "pulse.brainsand.space")
    Application.put_env(:pulse, :legacy_host, "pulse-david-baker.fly.dev")

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, old} -> Application.put_env(:pulse, key, old)
          :error -> Application.delete_env(:pulse, key)
        end
      end
    end)
  end

  test "old browser links preserve their path and query on the new domain" do
    conn =
      conn(
        :get,
        "https://pulse-david-baker.fly.dev/reset-password/example?return_to=%2Ffootprint"
      )
      |> CanonicalHost.call([])

    assert conn.status == 308
    assert conn.halted

    assert Plug.Conn.get_resp_header(conn, "location") ==
             ["https://pulse.brainsand.space/reset-password/example?return_to=%2Ffootprint"]
  end

  test "the canonical hostname does not redirect" do
    conn = conn(:get, "https://pulse.brainsand.space/login") |> CanonicalHost.call([])
    refute conn.halted
  end

  test "API requests and credential posts are not redirected between hosts" do
    for {method, path} <- [
          {:get, "/api/platform/work"},
          {:put, "/api/platform/results/2026-10-25"},
          {:post, "/login"}
        ] do
      conn = conn(method, "https://pulse-david-baker.fly.dev" <> path) |> CanonicalHost.call([])
      refute conn.halted
    end
  end
end
