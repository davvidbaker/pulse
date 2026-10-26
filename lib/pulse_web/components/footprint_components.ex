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
        <.footprint_categories categories={@result.data["categories"]} hours={@hours} />
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

  attr :categories, :map, required: true
  attr :hours, :float, required: true

  def footprint_categories(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
      <div :for={scope <- Pulse.Footprint.scopes()} class="rounded-xl bg-white p-3 min-w-0">
        <p class="text-sm text-slate-600">{label(scope)}</p>
        <p class="font-semibold">
          <%= if @categories[scope]["missing"] do %>
            Not fully estimated
          <% else %>
            {watts(@categories[scope]["source_kwh"], @hours)} W
          <% end %>
        </p>
        <details class="mt-2 text-xs text-slate-600 space-y-2">
          <summary class="cursor-pointer underline">
            {label(@categories[scope]["method"])}
          </summary>
          <p :if={@categories[scope]["day_count"]}>
            Full category estimated on {@categories[scope]["full_estimate_days"]} of {@categories[
              scope
            ]["day_count"]} available days.
          </p>
          <p :if={length(@categories[scope]["methods"] || []) > 1}>
            Methods: {Enum.map_join(@categories[scope]["methods"], ", ", &label/1)}
          </p>
          <p>{method_description(@categories[scope]["method"])}</p>
          <p>
            {energy(@categories[scope]["source_kwh"])} kWh attributed to the selected period.
          </p>
          <p :if={@categories[scope]["missing"]}>
            Missing is not zero: any recorded energy is included, but the full category is unknown.
          </p>
          <p :if={@categories[scope]["source_ref"]} class="break-words">
            Baseline reference: {@categories[scope]["source_ref"]}
          </p>
          <p
            :for={factor <- @categories[scope]["factors"] || []}
            class="break-words"
          >
            Input: {factor["quantity"]} {factor["unit"]} · {factor["quality"]} · {energy(
              factor["source_kwh"]
            )} source kWh. {factor["source_ref"]}
          </p>
        </details>
      </div>
    </div>
    """
  end

  attr :summary, :any, required: true
  slot :controls

  def pulse_hero(assigns) do
    assigns = assign(assigns, :segments, category_segments(assigns.summary))

    score =
      if assigns.summary.available_days > 0,
        do: watts(assigns.summary.total_kwh, assigns.summary.hours),
        else: "—"

    assigns = assign(assigns, :score, score)

    ~H"""
    <section id="pulse-hero" data-period={@summary.period} class="pulse-hero space-y-5">
      <div class="pulse-hero-header">
        <div>
          <h1 class="text-sm font-semibold uppercase tracking-widest text-slate-500">Your Pulse</h1>
          <p id="pulse-period-label" class="text-sm text-slate-600">
            {period_label(@summary.period)}
          </p>
        </div>
        <div role="group" aria-label="Score period" class="flex gap-2">{render_slot(@controls)}</div>
      </div>
      <div class="pulse-ring" style={"--score-digits: #{String.length(@score)}"}>
        <svg
          viewBox="0 0 100 100"
          class="pulse-ring-chart"
          role="group"
          aria-label="Energy category shares of the accounted footprint"
        >
          <circle cx="50" cy="50" r="46" fill="none" stroke="#e2e8f0" stroke-width="7" />
          <circle
            :for={segment <- @segments}
            :if={segment.share > 0}
            class="pulse-ring-segment"
            data-category={segment.scope}
            cx="50"
            cy="50"
            r="46"
            fill="none"
            stroke={segment.color}
            stroke-width="7"
            pathLength="100"
            stroke-dasharray={"#{segment.arc} #{100 - segment.arc}"}
            stroke-dashoffset={-segment.offset}
            transform="rotate(-90 50 50)"
            tabindex="0"
            role="img"
            aria-label={segment.description}
          >
            <title>{segment.description}</title>
          </circle>
        </svg>
        <div class="pulse-ring-center">
          <span id="pulse-hero-score" class="pulse-score pulse-hero-number">{@score}</span>
          <span class="pulse-hero-unit">watts</span>
        </div>
      </div>
      <p class="pulse-hero-caption">
        <%= if @summary.available_days > 0 do %>
          Estimated average power · includes upstream energy
        <% else %>
          No calculated days in this period yet.
        <% end %>
      </p>
      <div :if={@summary.available_days > 0} class="pulse-ring-key">
        <p class="text-xs text-slate-500 text-center mb-4">
          Ring shows shares of accounted energy. Unknown energy has no slice.
        </p>
        <div class="pulse-category-legend">
          <details
            :for={segment <- @segments}
            class="pulse-category-item"
            data-category={segment.scope}
          >
            <summary>
              <span
                class={["pulse-category-swatch", segment.missing and "is-partial"]}
                style={"--category-color: #{segment.color}"}
              >
              </span>
              <span class="min-w-0">
                <span class="block text-xs text-slate-600">{label(segment.scope)}</span>
                <span class="block text-sm font-semibold text-slate-900">
                  <%= if segment.missing and segment.kwh == 0 do %>
                    Unknown
                  <% else %>
                    {watts(segment.kwh, @summary.hours)} W
                    <span class="font-normal text-slate-500">· {percent(segment.share)}%</span>
                    <span :if={segment.missing} class="text-amber-800"> · partial</span>
                  <% end %>
                </span>
              </span>
            </summary>
            <p class="mt-2 text-xs text-slate-600 leading-relaxed">
              {method_description(@summary.categories[segment.scope]["method"])}
              <span :if={segment.missing}>
                The full category is unknown; any recorded energy is included.
              </span>
            </p>
          </details>
        </div>
      </div>
      <div class="flex flex-wrap justify-center gap-x-6 gap-y-2 text-xs text-slate-500">
        <p id="pulse-period-dates">
          {Calendar.strftime(@summary.from, "%b %d, %Y")} – {Calendar.strftime(
            @summary.to,
            "%b %d, %Y"
          )}
        </p>
        <p id="pulse-period-coverage">
          Days available: {@summary.available_days} / {@summary.total_days}
        </p>
      </div>
      <p
        :if={@summary.available_days < @summary.total_days}
        class="text-xs text-center text-amber-900"
      >
        Incomplete history. The average uses available days only; missing days are not counted as zero.
      </p>
      <p
        :if={@summary.available_days > 0 and @summary.missing_scopes != []}
        class="text-xs text-center text-amber-900"
      >
        Partial footprint · {length(@summary.missing_scopes)} categories are not fully estimated.
      </p>
      <p :if={@summary.dirty} class="text-xs text-center text-amber-900">
        Inputs changed. Some estimates are awaiting recalculation.
      </p>
      <%= if @summary.available_days > 0 do %>
        <details id="pulse-breakdown" class="border-t border-slate-200 pt-4 space-y-4">
          <summary class="cursor-pointer text-sm font-medium">
            Energy breakdown and assumptions
          </summary>
          <p class="text-sm text-slate-600">
            {energy(@summary.total_kwh)} source kWh across {@summary.hours} hours of available daily estimates.
            Today's estimate covers the full local day, not just time elapsed. This is not a live meter reading.
          </p>
          <p class="text-sm text-slate-600">
            Modeling range: {watts(@summary.lower_kwh, @summary.hours)}–{watts(
              @summary.upper_kwh,
              @summary.hours
            )} watts.
            Observed inputs: {round(@summary.observed_fraction * 100)}% of estimated energy.
            The range is not a statistical confidence interval.
          </p>
          <.footprint_categories categories={@summary.categories} hours={@summary.hours} />
          <a href="/footprint" class="text-sm underline">
            Daily inputs, population defaults and sources
          </a>
          <p class="text-xs text-slate-500">
            {@summary.timezone} · latest calculation {Calendar.strftime(
              @summary.calculated_at,
              "%Y-%m-%d %H:%M UTC"
            )}
          </p>
        </details>
      <% end %>
    </section>
    """
  end

  @category_colors %{
    "home_electricity" => "#0e7490",
    "home_heating" => "#ea580c",
    "ground_travel" => "#1e3a8a",
    "food" => "#70a53e",
    "remote_compute" => "#7c3aed",
    "flights" => "#38bdf8",
    "goods" => "#eab308",
    "services" => "#475569"
  }

  defp category_segments(summary) do
    total = Enum.sum(Enum.map(summary.categories, fn {_scope, data} -> data["source_kwh"] end))

    {segments, _offset} =
      Enum.map_reduce(Pulse.Footprint.scopes(), 0.0, fn scope, offset ->
        category = summary.categories[scope] || %{}
        kwh = category["source_kwh"] || 0
        share = if total > 0, do: kwh / total * 100, else: 0.0
        # Center a small separator at each boundary, including the closing boundary.
        gap = if share < 100, do: min(0.45, share / 4), else: 0

        description =
          "#{label(scope)}: #{percent(share)}% of accounted energy" <>
            if(category["missing"], do: "; full category unknown", else: "")

        {%{
           scope: scope,
           kwh: kwh,
           share: share,
           arc: share - gap,
           offset: offset + gap / 2,
           color: @category_colors[scope],
           missing: category["missing"] || false,
           description: description
         }, offset + share}
      end)

    segments
  end

  defp percent(value) when value > 0 and value < 0.1, do: "<0.1"
  defp percent(value), do: :erlang.float_to_binary(value * 1.0, decimals: 1)

  defp period_label(:day), do: "Today's average"
  defp period_label(:week), do: "This week's average · Monday through today"
  defp period_label(:month), do: "This month's average · month to date"

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
    value = round(kwh * 1000 / hours)
    digits = Integer.to_string(value)
    if value >= 10_000, do: String.replace(digits, ~r/\B(?=(\d{3})+(?!\d))/, ","), else: digits
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

  defp method_description("mixed"),
    do:
      "Combines the listed daily estimation methods. Inspect individual days under Inputs and assumptions for their evidence."

  defp method_description(_), do: "There is not enough information to estimate the full category."
  def label(value), do: value |> String.replace("_", " ") |> String.capitalize()
end
