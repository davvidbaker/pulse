defmodule PulseWeb.FootprintComponents do
  use Phoenix.Component
  attr :result, :any, default: nil

  def footprint_card(assigns) do
    assigns = assign(assigns, :hours, if(assigns.result, do: day_hours(assigns.result)))

    ~H"""
    <section
      id="daily-footprint"
      class="rounded-3xl border border-emerald-200 bg-emerald-50 p-6 space-y-5"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="text-lg font-semibold text-slate-900">Daily Pulse</h2>
          <p class="text-sm text-slate-600">Estimated average power · source-equivalent energy</p>
        </div>
        <a href="/footprint" class="text-sm font-medium underline">Inputs and assumptions</a>
      </div>
      <%= if @result do %>
        <p class="text-5xl font-bold text-slate-950">
          <span class="pulse-score">{watts(@result.data["total_kwh"], @hours)}</span>
          <span class="text-lg font-medium">watts</span>
        </p>
        <p class="text-sm text-slate-600">
          {energy(@result.data["total_kwh"])} kWh over this {@hours}-hour local day.
          This includes upstream energy; it is an estimate for the full day, not a live meter reading.
        </p>
        <p :if={@result.data["status"] == "partial"} class="font-semibold text-amber-900">
          Partial footprint — some categories are not yet estimated.
        </p>
        <p :if={@result.dirty} class="font-semibold text-amber-900">
          Inputs changed. Showing the previous result while the next calculation is pending.
        </p>
        <p class="text-sm text-slate-600">
          Modeling range: {watts(@result.data["lower_kwh"], @hours)}–{watts(
            @result.data["upper_kwh"],
            @hours
          )} watts average.
          Based on observed inputs: {round(@result.data["observed_fraction"] * 100)}% of estimated energy.
          This range is not a statistical confidence interval.
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <div :for={scope <- Pulse.Footprint.scopes()} class="rounded-xl bg-white p-3 min-w-0">
            <p class="text-sm text-slate-600">{label(scope)}</p>
            <p class="font-semibold">
              <%= if @result.data["categories"][scope]["missing"] do %>
                Not fully estimated
              <% else %>
                {watts(@result.data["categories"][scope]["source_kwh"], @hours)} W
              <% end %>
            </p>
            <details class="mt-2 text-xs text-slate-600 space-y-2">
              <summary class="cursor-pointer underline">
                {label(@result.data["categories"][scope]["method"])}
              </summary>
              <p>{method_description(@result.data["categories"][scope]["method"])}</p>
              <p>
                {energy(@result.data["categories"][scope]["source_kwh"])} kWh attributed to this day.
              </p>
              <p :if={@result.data["categories"][scope]["missing"]}>
                Missing is not zero: any recorded energy is included, but the full category is unknown.
              </p>
              <p :if={@result.data["categories"][scope]["source_ref"]} class="break-words">
                Baseline reference: {@result.data["categories"][scope]["source_ref"]}
              </p>
              <p
                :for={factor <- @result.data["categories"][scope]["factors"] || []}
                class="break-words"
              >
                Input: {factor["quantity"]} {factor["unit"]} · {factor["quality"]} · {energy(
                  factor["source_kwh"]
                )} source kWh. {factor["source_ref"]}
              </p>
            </details>
          </div>
        </div>
        <p class="text-xs text-slate-500">
          Accounting date: {@result.date} · {@result.data["timezone"]} · calculated {Calendar.strftime(
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

  def population_defaults(assigns) do
    ~H"""
    <details id="population-defaults" class="rounded-2xl border bg-white p-5 space-y-4">
      <summary class="cursor-pointer font-semibold">
        Which populations and assumptions does Pulse use?
      </summary>
      <p class="text-sm text-slate-600">
        These defaults belong to model pulse-energy-v1. They are coarse US estimates, not a demographic match to you.
        For each category, Pulse first uses the selected day's observations. For the unobserved share it prefers your personal history,
        then your saved baseline, then an available population default. Missing categories stay unknown.
      </p>
      <dl class="space-y-4 text-sm text-slate-700">
        <div>
          <dt class="font-semibold">Home electricity · US households</dt>
          <dd>
            <a
              class="underline"
              href="https://www.eia.gov/energyexplained/use-of-energy/electricity-use-in-homes.php"
            >
              EIA's household electricity summary
            </a>
            (page updated December 2023) gives about 10,500 delivered kWh per household per year.
            Pulse divides by 365 and your household size, then multiplies by your grid source factor.
            This is an annual national average, without local weather, home size or seasonal adjustment.
          </dd>
        </div>
        <div>
          <dt class="font-semibold">Home heating · US households using natural gas</dt>
          <dd>
            <a class="underline" href="https://www.eia.gov/todayinenergy/detail.php?id=57321">EIA RECS 2020</a>:
            56.6 million Btu per gas-using household per year. Pulse converts to kWh, divides by 365 and household size,
            and applies a 1.05 source factor. Electric heating is included in electricity; unknown heating remains missing.
          </dd>
        </div>
        <div>
          <dt class="font-semibold">Ground travel · licensed US drivers</dt>
          <dd>
            <a
              class="underline"
              href="https://www.fhwa.dot.gov/policyinformation/pubs/our_nations_highways_2026/drivers.cfm"
            >FHWA 2024</a>:
            13,735 vehicle-miles per licensed driver per year, about 60.6 km/day.
            Your daily distance and vehicle calibration override these inputs; an optional FuelEconomy.gov ID supplies model/year efficiency.
            The fallback 0.7 fuel kWh/km is an agent-selected vehicle proxy, not a measured fleet average.
            Fuel accounting currently excludes extraction and refining.
          </dd>
        </div>
        <div>
          <dt class="font-semibold">Food · US residents</dt>
          <dd>
            <a
              class="underline"
              href="https://www.ers.usda.gov/data-products/resource-requirements-of-food-demand"
            >USDA Resource Requirements of Food Demand</a>,
            2023 table Xf0000, TOTAL, released March 17, 2026, divided by the <a
              class="underline"
              href="https://www.census.gov/newsroom/facts-for-features/2024/fourth-of-july.html"
            >2023 Census population of 334,914,895</a>.
            Pulse subtracts shopping transport, kitchen equipment and household kitchen utilities to avoid double counting.
            The result is about 18.46 source kWh per person per day; a generic meal is one third of that.
            It describes food-system energy, not dietary calories or a particular meal.
          </dd>
        </div>
        <div>
          <dt class="font-semibold">Compute, flights, goods and services · no population default</dt>
          <dd>
            These need observations, your baseline or enough personal history. An empty category is not assumed to consume zero energy.
          </dd>
        </div>
        <div>
          <dt class="font-semibold">Personal history and shared energy</dt>
          <dd>
            History uses the median of at least three complete observed days in the preceding 28 days.
            If at least three match the weekday, it uses those. The initial household size of 2.5 is a modeling assumption you can edit.
            Observations spanning several dates are spread evenly; household totals are divided by household size.
          </dd>
        </div>
        <div>
          <dt class="font-semibold">Energy basis and uncertainty</dt>
          <dd>
            <a
              class="underline"
              href="https://www.energystar.gov/sites/default/files/asset/document/BPS-White_paper_final.pdf"
            >ENERGY STAR source-energy convention</a>:
            delivered electricity defaults to 2.8 source kWh per delivered kWh; gas uses 1.05.
            These are accounting factors, not local measurements. The scenario range is ±20% for observed energy and ±50% for inferred energy;
            it is not a statistical confidence interval. Average watts divides the day's source kWh by the actual hours in that local day, then multiplies by 1,000.
          </dd>
        </div>
      </dl>
    </details>
    """
  end

  def day_hours(result) do
    {first, last} = Pulse.Footprint.day_bounds(result.date, result.data["timezone"])
    DateTime.diff(last, first, :second) / 3600
  end

  defp watts(kwh, hours) do
    round(kwh * 1000 / hours)
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp energy(kwh), do: :erlang.float_to_binary(kwh * 1.0, decimals: 1)

  defp method_description("personal_history"),
    do: "Unobserved energy uses the median of recent complete observed days (up to 28 days)."

  defp method_description("personal_baseline"),
    do: "Unobserved energy uses the daily baseline you supplied."

  defp method_description("population_model"),
    do:
      "Unobserved energy uses the population model, with your configured household, travel and vehicle assumptions. See population details on Inputs and assumptions."

  defp method_description("observations"),
    do:
      "Complete category coverage comes from your observations; conversions can still use estimated factors."

  defp method_description("included_elsewhere"),
    do: "Energy is declared inside another category, or the profile declares no separate use."

  defp method_description(_), do: "There is not enough information to estimate the full category."
  def label(value), do: value |> String.replace("_", " ") |> String.capitalize()
end
