import Config

config :pulse, PulseWeb.Endpoint, server: true

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :pulse, Pulse.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :pulse, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :pulse, PulseWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  smtp_relay = System.get_env("SMTP_RELAY") || "smtp.sendgrid.net"
  smtp_username = System.get_env("SMTP_USERNAME") || raise "SMTP_USERNAME missing"
  smtp_password = System.get_env("SMTP_PASSWORD") || raise "SMTP_PASSWORD missing"
  smtp_port = String.to_integer(System.get_env("SMTP_PORT") || "587")

  config :pulse, Pulse.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_relay,
    username: smtp_username,
    password: smtp_password,
    port: smtp_port,
    tls: :always,
    auth: :always

  config :oban,
    repo: Pulse.Repo,
    queues: [
      default: String.to_integer(System.get_env("OBAN_DEFAULT_CONCURRENCY") || "10"),
      calculations: String.to_integer(System.get_env("OBAN_CALC_CONCURRENCY") || "5"),
      notifications: 2,
      suggestions: 2
    ]
end
