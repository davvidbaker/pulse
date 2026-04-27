import Config

config :pulse, Pulse.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "pulse_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :pulse, PulseWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_at_least_64_chars_long_replace_in_production_!!",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:pulse, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:pulse, ~w(--watch)]}
  ]

config :pulse, PulseWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/pulse_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :pulse, Pulse.Mailer, adapter: Swoosh.Adapters.Local

config :logger, level: :debug

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true
