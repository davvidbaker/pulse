defmodule Pulse.Mailer.Unconfigured do
  @moduledoc "Returns an explicit delivery error until production email is configured."
  use Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: {:error, :email_not_configured}
end
