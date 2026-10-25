import Config

config :pulse, PulseWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

config :logger, level: :info
config :swoosh, :api_client, false
