// Entry point for the build script in your package.json,
// loaded by Phoenix into the browser.
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import Chart from "chart.js/auto"

// LiveView Hooks
const Hooks = {}

// Daily canonical estimates, with null values preserving missing-day gaps.
Hooks.PulseChart = {
  mounted() {
    const data = JSON.parse(this.el.dataset.chart)
    const watts = value => `${Math.round(value).toLocaleString("en-US", {useGrouping: Math.abs(value) >= 10000})} W`
    this.chart = new Chart(this.el.getContext("2d"), {
      type: "line",
      data: {
        labels: data.labels,
        datasets: [{
          label: "Average watts",
          data: data.watts,
          borderColor: "#059669",
          backgroundColor: "#059669",
          pointRadius: 4,
          spanGaps: false
        }]
      },
      options: {
        responsive: true,
        animation: false,
        maintainAspectRatio: false,
        scales: {y: {beginAtZero: true, ticks: {callback: watts}}},
        plugins: {
          legend: {display: false},
          tooltip: {callbacks: {label: ctx => watts(ctx.raw)}}
        }
      }
    })
    this.handleEvent("pulse_chart_updated", ({data}) => {
      this.chart.data.labels = data.labels
      this.chart.data.datasets[0].data = data.watts
      this.chart.update()
    })
  },
  destroyed() {
    this.chart?.destroy()
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
