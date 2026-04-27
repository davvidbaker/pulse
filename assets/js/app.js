// Entry point for the build script in your package.json,
// loaded by Phoenix into the browser.
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Import Chart.js (loaded from CDN via script tag in root.html.heex)
// or: import Chart from "chart.js/auto"

// LiveView Hooks
const Hooks = {}

/**
 * EnergyChart hook
 * Renders a Chart.js bar chart for daily energy costs.
 * Listens for "chart_data_updated" push events to refresh the chart.
 */
Hooks.EnergyChart = {
  mounted() {
    const rawData = this.el.dataset.chart
    const data = rawData ? JSON.parse(rawData) : { labels: [], costs: [], kwh: [] }
    this.chart = this.buildChart(data)

    this.handleEvent("chart_data_updated", ({ data }) => {
      this.chart.data.labels = data.labels
      this.chart.data.datasets[0].data = data.costs
      this.chart.data.datasets[1].data = data.kwh
      this.chart.update()
    })
  },

  buildChart(data) {
    const ctx = this.el.getContext("2d")
    return new Chart(ctx, {
      type: "bar",
      data: {
        labels: data.labels,
        datasets: [
          {
            label: "Cost ($)",
            data: data.costs,
            backgroundColor: "rgba(34, 197, 94, 0.7)",
            borderColor: "rgba(34, 197, 94, 1)",
            borderWidth: 1,
            yAxisID: "y"
          },
          {
            label: "kWh",
            data: data.kwh,
            backgroundColor: "rgba(59, 130, 246, 0.5)",
            borderColor: "rgba(59, 130, 246, 1)",
            borderWidth: 1,
            type: "line",
            yAxisID: "y1"
          }
        ]
      },
      options: {
        responsive: true,
        interaction: { mode: "index", intersect: false },
        scales: {
          y: {
            type: "linear",
            display: true,
            position: "left",
            ticks: { callback: v => "$" + v.toFixed(2) }
          },
          y1: {
            type: "linear",
            display: true,
            position: "right",
            grid: { drawOnChartArea: false },
            ticks: { callback: v => v + " kWh" }
          }
        },
        plugins: {
          legend: { position: "top" },
          tooltip: {
            callbacks: {
              label: (ctx) => {
                const label = ctx.dataset.label || ""
                if (label.includes("Cost")) return `${label}: $${ctx.raw.toFixed(3)}`
                return `${label}: ${ctx.raw.toFixed(3)}`
              }
            }
          }
        }
      }
    })
  },

  destroyed() {
    if (this.chart) this.chart.destroy()
  }
}

// Progress bar
topbar.config({ barColors: { 0: "#22c55e" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Connect LiveSocket
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  hooks: Hooks,
  params: { _csrf_token: csrfToken }
})

liveSocket.connect()
window.liveSocket = liveSocket
