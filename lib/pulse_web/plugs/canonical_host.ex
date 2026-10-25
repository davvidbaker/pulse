defmodule PulseWeb.Plugs.CanonicalHost do
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    host = Application.get_env(:pulse, :canonical_host)
    legacy = Application.get_env(:pulse, :legacy_host)

    if is_binary(host) and host != conn.host and conn.host == legacy and
         conn.method in ["GET", "HEAD"] and not String.starts_with?(conn.request_path, "/api/") do
      query = if conn.query_string == "", do: "", else: "?" <> conn.query_string

      conn
      |> put_resp_header("location", "https://" <> host <> conn.request_path <> query)
      |> send_resp(308, "")
      |> halt()
    else
      conn
    end
  end
end
