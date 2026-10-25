defmodule PulseWeb.FootprintComponents do
  use Phoenix.Component
  attr :result, :any, default: nil

  def footprint_card(assigns) do
    ~H"""
    <section
      id="daily-footprint"
      class="rounded-3xl border border-emerald-200 bg-emerald-50 p-6 space-y-5"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="text-lg font-semibold text-slate-900">Daily Pulse</h2>
          <p class="text-sm text-slate-600">
            Estimated full-day energy footprint · source-equivalent kWh
          </p>
        </div>
        <a href="/footprint" class="text-sm font-medium underline">Inputs and assumptions</a>
      </div>
      <%= if @result do %>
        <p class="text-5xl font-black text-slate-950">
          {Float.round(@result.data["total_kwh"] * 1.0, 1)}
          <span class="text-lg font-medium">kWh/day</span>
        </p>
        <p :if={@result.data["status"] == "partial"} class="font-semibold text-amber-900">
          Partial footprint — some categories are not yet estimated.
        </p>
        <p :if={@result.dirty} class="font-semibold text-amber-900">
          Inputs changed. Showing the previous result while the next calculation is pending.
        </p>
        <p class="text-sm text-slate-600">
          Modeling range: {Float.round(@result.data["lower_kwh"] * 1.0, 1)}–{Float.round(
            @result.data["upper_kwh"] * 1.0,
            1
          )} kWh.
          Based on observed inputs: {round(@result.data["observed_fraction"] * 100)}% of estimated energy.
          This range is not a statistical confidence interval.
        </p>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div :for={scope <- Pulse.Footprint.scopes()} class="rounded-xl bg-white p-3">
            <p class="text-sm text-slate-600">{label(scope)}</p>
            <p class="font-semibold">
              <%= if @result.data["categories"][scope]["missing"] do %>
                Not fully estimated
              <% else %>
                {Float.round(@result.data["categories"][scope]["source_kwh"] * 1.0, 1)} kWh
              <% end %>
            </p>
            <p class="text-xs text-slate-500">{label(@result.data["categories"][scope]["method"])}</p>
          </div>
        </div>
        <p class="text-xs text-slate-500">
          Accounting date: {@result.date} · calculated {Calendar.strftime(
            @result.calculated_at,
            "%Y-%m-%d %H:%M UTC"
          )} ·
          Flambe receipts: {map_size(@result.receipts)}/{length(Pulse.Footprint.kinds())}
        </p>
      <% else %>
        <p class="text-4xl font-black">—</p>
        <p>
          Waiting for the first calculation. Review your assumptions and add observations below; automatic refreshes need the data platform connection.
        </p>
      <% end %>
    </section>
    """
  end

  def label(value), do: value |> String.replace("_", " ") |> String.capitalize()
end
