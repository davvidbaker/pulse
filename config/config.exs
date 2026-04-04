import Config

config :pulse,
  ecto_repos: [Pulse.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :pulse, PulseWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PulseWeb.ErrorHTML, json: PulseWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Pulse.PubSub,
  live_view: [signing_salt: "8xKgH7Vz"]

config :pulse, Pulse.Mailer, adapter: Swoosh.Adapters.Local

config :esbuild,
  version: "0.25.0",
  pulse: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.0.9",
  pulse: [
    args: ~w(--input=css/app.css --output=../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :oban,
  repo: Pulse.Repo,
  queues: [default: 10, calculations: 5, notifications: 2, suggestions: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       # Rebuild daily summaries at 00:05 UTC
       {"5 0 * * *", Pulse.Workers.SummaryWorker},
       # Generate suggestions at 02:00 UTC
       {"0 2 * * *", Pulse.Workers.SuggestionWorker},
       # Send weekly summary notifications every Monday at 08:00 UTC
       {"0 8 * * 1", Pulse.Workers.NotificationWorker, args: %{type: "weekly_summary"}}
     ]}
  ]

import_config "#{config_env()}.exs"
