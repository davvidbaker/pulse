defmodule PulseWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time", unit: {:native, :millisecond}),
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.start.system_time", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.exception.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.socket_connected.duration", unit: {:native, :millisecond}),
      summary("phoenix.channel_join.duration", unit: {:native, :millisecond}),
      summary("phoenix.channel_handled_in.duration", unit: {:native, :millisecond}),
      # Ecto Metrics
      summary("pulse.repo.query.total_time", unit: {:native, :millisecond}),
      summary("pulse.repo.query.decode_time", unit: {:native, :millisecond}),
      summary("pulse.repo.query.query_time", unit: {:native, :millisecond}),
      summary("pulse.repo.query.queue_time", unit: {:native, :millisecond}),
      summary("pulse.repo.query.idle_time", unit: {:native, :millisecond}),
      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :dispatch_ecto_stats, []}
    ]
  end

  def dispatch_ecto_stats do
    Ecto.Adapters.SQL.Sandbox
  end
end
