defmodule Pulse.Mailer do
  use Swoosh.Mailer, otp_app: :pulse

  def delivery_available? do
    Application.get_env(:pulse, __MODULE__, [])[:adapter] != Pulse.Mailer.Unconfigured
  end
end
