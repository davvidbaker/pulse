// Entry point for the build script in your package.json,
// loaded by Phoenix into the browser.
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import * as Plot from "@observablehq/plot"

// LiveView Hooks
const Hooks = {}

// Render at the container's actual width; SVG stays sharp at any pixel density.
Hooks.PulseChart = {
  mounted() {
    this.data = JSON.parse(this.el.dataset.chart)
    this.renderPlot()
    this.resizeObserver = new ResizeObserver(() => {
      if (Math.floor(this.el.getBoundingClientRect().width) !== this.width) this.renderPlot()
    })
    this.resizeObserver.observe(this.el)
    this.handleEvent("pulse_chart_updated", ({data}) => {
      this.data = data
      this.renderPlot()
    })
  },

  renderPlot() {
    this.width = Math.floor(this.el.getBoundingClientRect().width)
    if (this.width < 1) return
    const points = this.data.labels.map((date, i) => ({date, watts: this.data.watts[i]}))
    const known = points.filter(d => d.watts !== null && Number.isFinite(d.watts))
    const maximum = Math.max(10, ...known.map(d => d.watts))
    const tickCount = Math.min(points.length, Math.max(2, Math.floor((this.width - 96) / 75)))
    const ticks = Array.from({length: tickCount}, (_, i) =>
      this.data.labels[tickCount === 1 ? 0 : Math.round(i * (points.length - 1) / (tickCount - 1))])
    const watts = value => `${Math.round(value).toLocaleString("en-US", {useGrouping: Math.abs(value) >= 10000})} W`
    const dateLabel = date => new Date(`${date}T12:00:00Z`).toLocaleDateString("en-US", {month: "short", day: "numeric", timeZone: "UTC"})
    this.el.replaceChildren(Plot.plot({
      width: this.width,
      height: 280,
      marginLeft: 76,
      marginRight: 20,
      marginBottom: 38,
      ariaLabel: "Daily average power in watts",
      ariaDescription: "Vertical axis starts at zero. Missing days remain gaps.",
      style: {fontFamily: "inherit", fontSize: "12px", background: "transparent", color: "#64748b"},
      x: {type: "point", domain: this.data.labels, ticks, tickFormat: dateLabel, label: null, padding: 0.5},
      y: {domain: [0, maximum * 1.1], nice: true, grid: true, ticks: 5, tickFormat: watts, label: null},
      marks: [
        Plot.ruleY([0], {stroke: "#94a3b8"}),
        // Keep null rows in the line so missing dates break the path.
        Plot.line(points, {x: "date", y: "watts", stroke: "#059669", strokeWidth: 2}),
        Plot.dot(known, {x: "date", y: "watts", fill: "#059669", r: 4, title: d => `${d.date}: ${watts(d.watts)}`})
      ]
    }))
  },

  destroyed() {
    this.resizeObserver.disconnect()
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
