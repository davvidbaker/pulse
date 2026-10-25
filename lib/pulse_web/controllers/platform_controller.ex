defmodule PulseWeb.PlatformController do
  use PulseWeb, :controller
  alias Pulse.Footprint

  def work(conn, _), do: json(conn, %{dates: Footprint.work_dates(conn.assigns.platform_user)})

  def inputs(conn, %{"date" => value}),
    do:
      with_date(conn, value, fn day ->
        json(conn, Footprint.inputs(conn.assigns.platform_user, day))
      end)

  def result(conn, %{"date" => value}) do
    with_date(conn, value, fn day ->
      case Footprint.result(conn.assigns.platform_user.id, day) do
        nil -> conn |> put_status(404) |> json(%{error: "not_found"})
        row -> json(conn, Footprint.export_result(row))
      end
    end)
  end

  def save_result(conn, %{"date" => value} = params) do
    with_date(conn, value, fn day ->
      respond(
        conn,
        Footprint.save_result(
          conn.assigns.platform_user,
          day,
          Map.delete(params, "date") |> Map.put("date", value)
        )
      )
    end)
  end

  def receipt(conn, %{"date" => value} = params) do
    with_date(conn, value, fn day ->
      respond(
        conn,
        Footprint.receipt(
          conn.assigns.platform_user.id,
          day,
          params["revision"],
          params["kind"],
          params["observation_id"]
        )
      )
    end)
  end

  def observe(conn, %{"observation" => attrs}) when is_map(attrs) do
    case Footprint.put_observation(conn.assigns.platform_user.id, attrs) do
      {:ok, row} -> json(conn, %{id: row.id})
      {:error, _} -> conn |> put_status(422) |> json(%{error: "invalid_observation"})
    end
  end

  def observe(conn, _), do: conn |> put_status(422) |> json(%{error: "invalid_observation"})
  defp respond(conn, {:ok, row}), do: json(conn, Footprint.export_result(row))

  defp respond(conn, {:error, reason}) do
    status = if reason == :stale_inputs, do: 409, else: 422
    conn |> put_status(status) |> json(%{error: to_string(reason)})
  end

  defp with_date(conn, value, fun) do
    case Date.from_iso8601(value) do
      {:ok, day} ->
        if Date.compare(day, ~D[2020-01-01]) != :lt,
          do: fun.(day),
          else: conn |> put_status(422) |> json(%{error: "invalid_date"})

      _ ->
        conn |> put_status(422) |> json(%{error: "invalid_date"})
    end
  end
end
