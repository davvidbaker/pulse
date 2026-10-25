defmodule PulseWeb.FootprintLive do
  use PulseWeb, :live_view
  import PulseWeb.FootprintComponents
  alias Pulse.Footprint
  alias Pulse.Footprint.{Profile, Observation}

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 60_000)
    user = socket.assigns.current_user
    day = Footprint.local_today(user)

    {:ok,
     socket
     |> assign(:page_title, "Energy footprint")
     |> assign(:day, day)
     |> assign(
       :profile_form,
       to_form(Profile.changeset(Footprint.profile(user.id), %{}), as: :profile)
     )
     |> assign(:observation_form, new_observation(day))
     |> reload()}
  end

  @impl true
  def handle_params(params, _, socket) do
    day =
      case Date.from_iso8601(params["date"] || "") do
        {:ok, day} -> day
        _ -> Footprint.local_today(socket.assigns.current_user)
      end

    {:noreply, socket |> assign(:day, day) |> reload()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 60_000)
    {:noreply, reload(socket)}
  end

  @impl true
  def handle_event("save_profile", %{"profile" => attrs}, socket) do
    case Footprint.update_profile(socket.assigns.current_user.id, attrs) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(:profile_form, to_form(Profile.changeset(profile, %{}), as: :profile))
         |> reload()
         |> put_flash(:info, "Assumptions saved. A calculation is pending.")}

      {:error, cs} ->
        {:noreply, assign(socket, :profile_form, to_form(cs, as: :profile))}
    end
  end

  def handle_event("save_observation", %{"observation" => attrs}, socket) do
    case Footprint.put_observation(socket.assigns.current_user.id, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:observation_form, new_observation(socket.assigns.day))
         |> reload()
         |> put_flash(:info, "Observation saved. A calculation is pending.")}

      {:error, cs} ->
        {:noreply, assign(socket, :observation_form, to_form(cs, as: :observation))}
    end
  end

  def handle_event("delete_observation", %{"id" => id}, socket) do
    Footprint.delete_observation(socket.assigns.current_user.id, id)
    {:noreply, reload(socket)}
  end

  def handle_event("show_date", %{"date" => day}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/footprint?date=#{day}")}

  defp new_observation(day),
    do:
      to_form(
        Observation.changeset(%Observation{}, %{
          "starts_on" => day,
          "ends_on" => day,
          "unit" => "kwh",
          "scope" => "home_electricity"
        }),
        as: :observation
      )

  defp reload(socket) do
    user_id = socket.assigns.current_user.id

    socket
    |> assign(:result, Footprint.result(user_id, socket.assigns.day))
    |> assign(:observations, Footprint.list_observations(user_id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <h1 class="text-2xl font-bold">Your energy footprint</h1>
      <.form for={%{}} phx-submit="show_date" class="flex items-end gap-3">
        <.input name="date" type="date" value={@day} label="Accounting date" />
        <.button>Show day</.button>
      </.form>
      <.footprint_card result={@result} />
      <p class="text-sm text-slate-600">
        Pulse estimates a full day, updating as evidence arrives. Home electricity includes local devices and cooking. Food defaults exclude those utilities, shopping travel and kitchen equipment. Unknown categories stay visible. Carbon emissions are a separate metric.
      </p>
      <div class="grid lg:grid-cols-2 gap-8">
        <section class="rounded-2xl bg-white border p-5 space-y-4">
          <h2 class="text-lg font-semibold">Add an observation</h2>
          <p class="text-sm text-slate-600">
            Enter usage or a sourced energy estimate. For a utility bill or an allocated purchase, specify the covered dates: its quantity is spread evenly across those days. Coverage describes how much of that category's full day is represented; complete observations replace defaults.
          </p>
          <.form for={@observation_form} phx-submit="save_observation" class="space-y-3">
            <.select
              field={@observation_form[:scope]}
              label="Category"
              options={Enum.map(Footprint.scopes(), &{label(&1), &1})}
            />
            <div class="grid grid-cols-2 gap-3">
              <.input field={@observation_form[:starts_on]} type="date" label="First day" />
              <.input field={@observation_form[:ends_on]} type="date" label="Last day" />
              <.input
                field={@observation_form[:quantity]}
                type="number"
                step="any"
                min="0"
                label="Total quantity (zero is valid)"
              />
              <.select
                field={@observation_form[:unit]}
                label="Unit"
                options={~w(kwh km liter therm meal usd night item hour request)}
              />
            </div>
            <.select
              field={@observation_form[:basis]}
              label="Energy basis after unit conversion"
              options={[
                {"Source energy", "source"},
                {"Delivered electricity", "electricity"},
                {"Natural gas", "gas"},
                {"Vehicle fuel", "fuel"}
              ]}
            />
            <.input
              field={@observation_form[:factor_kwh_per_unit]}
              type="number"
              step="any"
              min="0"
              label="Energy kWh per unit (required for custom units)"
            />
            <.input
              field={@observation_form[:source_ref]}
              label="Source or methodology"
              placeholder="Meter, provider report, or factor reference"
            />
            <.input
              field={@observation_form[:coverage]}
              type="number"
              step="0.01"
              min="0"
              max="1"
              label="Fraction of full day covered (1 = complete category total)"
            />
            <.input
              field={@observation_form[:allocation]}
              type="number"
              step="0.01"
              min="0"
              max="1"
              label="Your allocation (1 = all; 0.5 = half)"
            />
            <.input
              field={@observation_form[:household]}
              type="checkbox"
              label="Household total: also divide by household size"
            />
            <.select
              field={@observation_form[:quality]}
              label="Input quality"
              options={[{"Estimate", "estimated"}, {"Measured activity", "measured"}]}
            />
            <.select
              field={@observation_form[:included_in_scope]}
              label="Already included in another category?"
              options={[{"No, add this energy", ""} | Enum.map(Footprint.scopes(), &{label(&1), &1})]}
            />
            <.button>Save observation</.button>
          </.form>
        </section>
        <section class="rounded-2xl bg-white border p-5 space-y-4">
          <h2 class="text-lg font-semibold">Your assumptions</h2>
          <p class="text-sm text-slate-600">
            Initial assumptions are US averages and a generic vehicle proxy. The initial household allocation assumes 2.5 people. Replace them with your own values. Complete observed days take priority over these baselines.
          </p>
          <.form for={@profile_form} phx-submit="save_profile" class="space-y-3">
            <.input
              field={@profile_form[:household_size]}
              type="number"
              step="0.1"
              min="1"
              label="Household size"
            />
            <.input
              field={@profile_form[:grid_source_factor]}
              type="number"
              step="0.01"
              min="1"
              label="Grid source energy per delivered kWh (US convention: 2.8)"
            />
            <.select
              field={@profile_form[:heating]}
              label="Home heating"
              options={[
                {"Unknown", "unknown"},
                {"Natural gas", "gas"},
                {"Electric (inside electricity)", "electric"},
                {"None", "none"}
              ]}
            />
            <.input
              field={@profile_form[:drives]}
              type="checkbox"
              label="Use a driving baseline when travel is unobserved"
            />
            <.input
              field={@profile_form[:daily_travel_km]}
              type="number"
              step="any"
              min="0"
              label="Typical daily driving km (blank uses US driver average)"
            />
            <.input
              field={@profile_form[:vehicle_kwh_per_km]}
              type="number"
              step="0.001"
              min="0"
              label="Personal vehicle kWh/km (blank uses model lookup or 0.7 proxy)"
            />
            <.select
              field={@profile_form[:vehicle_energy_basis]}
              label="Personal vehicle efficiency basis"
              options={[
                {"Fuel energy", "fuel"},
                {"Delivered electricity", "electricity"},
                {"Source energy", "source"}
              ]}
            />
            <.input
              field={@profile_form[:vehicle_id]}
              label="FuelEconomy.gov vehicle ID (optional model/year lookup)"
            />
            <div class="border-t pt-3 space-y-3">
              <p class="text-sm font-medium">Personal daily baselines in source kWh</p>
              <p class="text-xs text-slate-500">
                Blank uses history or available defaults. Explicit zero means you declare no use for that category.
              </p>
              <.input
                :for={scope <- Footprint.scopes()}
                name={"profile[baselines][#{scope}]"}
                type="number"
                step="any"
                min="0"
                value={Phoenix.HTML.Form.input_value(@profile_form, :baselines)[scope]}
                label={label(scope)}
              />
            </div>
            <.button>Save assumptions</.button>
          </.form>
          <p class="text-xs text-slate-500">
            Set your accounting timezone in <a href="/settings" class="underline">Settings</a>. Goods, flights, services and remote compute need your observations or explicit baselines; there is no universal per-prompt AI factor.
          </p>
        </section>
      </div>
      <section class="rounded-2xl bg-white border p-5 space-y-3">
        <h2 class="text-lg font-semibold">Recent observations</h2>
        <p :if={@observations == []} class="text-slate-500">No observations yet.</p>
        <div
          :for={o <- @observations}
          class="flex flex-wrap justify-between items-center border-b py-3 gap-3"
        >
          <div>
            <p class="font-medium">{label(o.scope)} · {o.quantity} {o.unit}</p>
            <p class="text-xs text-slate-500">
              {o.starts_on}–{o.ends_on} · {o.source_ref || "User entry"}
            </p>
          </div>
          <button
            phx-click="delete_observation"
            phx-value-id={o.id}
            data-confirm="Delete this observation?"
            class="text-sm text-red-700"
          >
            Delete
          </button>
        </div>
      </section>
    </div>
    """
  end
end
