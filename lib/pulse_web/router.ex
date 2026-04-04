defmodule PulseWeb.Router do
  use PulseWeb, :router

  import PulseWeb.UserAuth

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {PulseWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # Public routes
  scope "/", PulseWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
  end

  # Authentication routes
  scope "/", PulseWeb do
    pipe_through([:browser, :redirect_if_user_is_authenticated])

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{PulseWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live("/register", UserRegistrationLive, :new)
      live("/login", UserLoginLive, :new)
      live("/reset-password", UserForgotPasswordLive, :new)
      live("/reset-password/:token", UserResetPasswordLive, :edit)
    end

    post("/login", UserSessionController, :create)
  end

  # Authenticated routes
  scope "/", PulseWeb do
    pipe_through([:browser, :require_authenticated_user])

    live_session :require_authenticated_user,
      on_mount: [{PulseWeb.UserAuth, :ensure_authenticated}] do
      live("/dashboard", DashboardLive, :index)
      live("/setup", SetupLive, :index)
      live("/setup/new", SetupLive, :new)
      live("/setup/:id/edit", SetupLive, :edit)
      live("/logs", LogsLive, :index)
      live("/logs/:id", LogsLive, :show)
      live("/notifications", NotificationsLive, :index)
      live("/badges", BadgesLive, :index)
      live("/settings", SettingsLive, :index)

      live("/confirm-email/:token", UserConfirmationLive, :edit)
      live("/users/settings", UserSettingsLive, :edit)
      live("/users/settings/confirm-email/:token", UserSettingsLive, :confirm_email)
    end
  end

  scope "/", PulseWeb do
    pipe_through([:browser])

    delete("/logout", UserSessionController, :delete)

    live_session :current_user,
      on_mount: [{PulseWeb.UserAuth, :mount_current_user}] do
      live("/confirm", UserConfirmationInstructionsLive, :new)
    end
  end

  # Dev routes
  if Application.compile_env(:pulse, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: PulseWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
