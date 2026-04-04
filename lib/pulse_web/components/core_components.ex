defmodule PulseWeb.CoreComponents do
  @moduledoc """
  Provides core UI components used across Pulse LiveViews.
  """
  use Phoenix.Component
  use PulseWeb, :verified_routes

  import PulseWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc "Flash message group"
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div class="space-y-2">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  attr :kind, :atom, values: [:info, :error]
  attr :flash, :map, required: true

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      class={[
        "rounded-lg px-4 py-3 text-sm font-medium",
        @kind == :info && "bg-green-50 text-green-800 border border-green-200",
        @kind == :error && "bg-red-50 text-red-800 border border-red-200"
      ]}
    >
      <%= msg %>
    </div>
    """
  end

  @doc "A modal dialog component."
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      class="hidden relative z-50"
    >
      <div class="fixed inset-0 bg-black/40" aria-hidden="true" />
      <div class="fixed inset-0 overflow-y-auto">
        <div class="flex min-h-full items-center justify-center p-4">
          <div
            class="bg-white rounded-xl shadow-xl w-full max-w-lg p-6"
            phx-click-away={@on_cancel}
            phx-window-keydown={@on_cancel}
            phx-key="escape"
          >
            <%= render_slot(@inner_block) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(to: "##{id} [data-modal-bg]", transition: {"ease-out duration-200", "opacity-0", "opacity-100"})
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(to: "##{id}", transition: {"ease-in duration-100", "opacity-100", "opacity-0"})
  end

  @doc "Stat card for the dashboard"
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :unit, :string, default: ""
  attr :trend, :string, default: nil

  def stat_card(assigns) do
    ~H"""
    <div class="bg-white rounded-xl p-6 shadow-sm border border-gray-100">
      <p class="text-sm text-gray-500 mb-1"><%= @label %></p>
      <p class="text-3xl font-bold text-gray-900">
        <%= @value %><span class="text-base font-normal text-gray-500 ml-1"><%= @unit %></span>
      </p>
      <p :if={@trend} class="text-xs text-gray-400 mt-1"><%= @trend %></p>
    </div>
    """
  end

  @doc "Suggestion card"
  attr :suggestion, :map, required: true
  attr :on_dismiss, JS, default: %JS{}

  def suggestion_card(assigns) do
    ~H"""
    <div class="bg-amber-50 border border-amber-200 rounded-lg p-4 flex justify-between items-start gap-4">
      <div>
        <p class="font-medium text-amber-900 text-sm"><%= @suggestion.title %></p>
        <p class="text-amber-700 text-sm mt-0.5"><%= @suggestion.body %></p>
        <p :if={not is_nil(@suggestion.estimated_saving_weekly) and Decimal.gt?(@suggestion.estimated_saving_weekly, Decimal.new(0))}
           class="text-xs text-amber-600 mt-1 font-medium">
          Save ~$<%= Decimal.round(@suggestion.estimated_saving_weekly, 2) %>/week
        </p>
      </div>
      <button
        phx-click="dismiss_suggestion"
        phx-value-id={@suggestion.id}
        class="text-amber-400 hover:text-amber-600 shrink-0"
        aria-label="Dismiss"
      >
        ✕
      </button>
    </div>
    """
  end

  @doc "Source type badge"
  attr :source_type, :string, required: true

  def source_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
      @source_type == "electricity" && "bg-yellow-100 text-yellow-800",
      @source_type == "gas" && "bg-orange-100 text-orange-800",
      @source_type == "fuel" && "bg-blue-100 text-blue-800",
      @source_type == "water" && "bg-cyan-100 text-cyan-800",
      @source_type == "heating" && "bg-red-100 text-red-800"
    ]}>
      <%= source_icon(@source_type) %> <%= String.capitalize(@source_type) %>
    </span>
    """
  end

  defp source_icon("electricity"), do: "⚡"
  defp source_icon("gas"), do: "🔥"
  defp source_icon("fuel"), do: "⛽"
  defp source_icon("water"), do: "💧"
  defp source_icon("heating"), do: "🌡️"
  defp source_icon(_), do: "📦"

  @doc "Simple button"
  attr :type, :string, default: "button"
  attr :variant, :atom, values: [:primary, :secondary, :danger], default: :primary
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "px-4 py-2 rounded-lg text-sm font-medium transition focus:outline-none focus:ring-2 focus:ring-offset-2",
        @variant == :primary && "bg-green-600 text-white hover:bg-green-700 focus:ring-green-500",
        @variant == :secondary && "border border-gray-300 text-gray-700 hover:bg-gray-50 focus:ring-gray-400",
        @variant == :danger && "bg-red-600 text-white hover:bg-red-700 focus:ring-red-500",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc "Form input with label and error"
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :type, :string, default: "text"
  attr :errors, :list, default: []
  attr :rest, :global, include: ~w(placeholder required min max step)
  slot :inner_block

  def input(assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id} class="block text-sm font-medium text-gray-700 mb-1">
        <%= @label %>
      </label>
      <input
        id={@id}
        name={@name}
        type={@type}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "block w-full rounded-lg border px-3 py-2 text-sm text-gray-900 shadow-sm focus:outline-none focus:ring-2 focus:ring-green-500",
          @errors == [] && "border-gray-300",
          @errors != [] && "border-red-400 focus:ring-red-400"
        ]}
        {@rest}
      />
      <p :for={error <- @errors} class="mt-1 text-xs text-red-600"><%= error %></p>
    </div>
    """
  end

  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :options, :list, default: []
  attr :errors, :list, default: []
  attr :rest, :global

  def select(assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id} class="block text-sm font-medium text-gray-700 mb-1">
        <%= @label %>
      </label>
      <select
        id={@id}
        name={@name}
        class="block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm focus:outline-none focus:ring-2 focus:ring-green-500"
        {@rest}
      >
        <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
      </select>
      <p :for={error <- @errors} class="mt-1 text-xs text-red-600"><%= error %></p>
    </div>
    """
  end
end
