defmodule PulseWeb.PageController do
  use PulseWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/dashboard")
    else
      render(conn, :home)
    end
  end
end
