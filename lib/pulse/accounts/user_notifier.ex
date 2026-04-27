defmodule Pulse.Accounts.UserNotifier do
  import Swoosh.Email

  alias Pulse.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Pulse", "no-reply@pulse.app"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your Pulse account", """
    Hi #{user.email},

    Please confirm your Pulse account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.
    """)
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your Pulse password", """
    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)
  end

  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update your Pulse email", """
    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)
  end
end
