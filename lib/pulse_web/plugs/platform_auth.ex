defmodule PulseWeb.PlatformAuth do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _opts) do
    expected = Application.get_env(:pulse, :platform_token)
    user_id = Application.get_env(:pulse, :platform_user_id)

    supplied =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> value] -> value
        _ -> ""
      end

    if is_binary(expected) and byte_size(expected) >= 32 and
         byte_size(supplied) == byte_size(expected) and
         Plug.Crypto.secure_compare(supplied, expected) and is_binary(user_id) and
         Ecto.UUID.cast(user_id) != :error do
      case Pulse.Repo.get(Pulse.Accounts.User, user_id) do
        nil -> reject(conn)
        user -> assign(conn, :platform_user, user)
      end
    else
      reject(conn)
    end
  end

  defp reject(conn),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, ~s({"error":"unauthorized"}))
      |> halt()
end
