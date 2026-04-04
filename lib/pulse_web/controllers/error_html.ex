defmodule PulseWeb.ErrorHTML do
  use PulseWeb, :html

  def render("404.html", _assigns) do
    "Not Found"
  end

  def render("500.html", _assigns) do
    "Internal Server Error"
  end
end
