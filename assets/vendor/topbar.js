let visible = false
let progressBar = null
let config = {
  barColors: { 0: "#29d" },
  shadowColor: "rgba(0, 0, 0, 0.3)"
}

function ensureBar() {
  if (progressBar) return progressBar

  progressBar = document.createElement("div")
  progressBar.setAttribute("data-topbar", "true")
  progressBar.style.position = "fixed"
  progressBar.style.top = "0"
  progressBar.style.left = "0"
  progressBar.style.height = "3px"
  progressBar.style.width = "0%"
  progressBar.style.zIndex = "9999"
  progressBar.style.transition = "width 250ms ease, opacity 200ms ease"
  progressBar.style.opacity = "0"
  progressBar.style.background = config.barColors[0]
  progressBar.style.boxShadow = `0 0 10px ${config.shadowColor}`
  document.body.appendChild(progressBar)

  return progressBar
}

const topbar = {
  config(options = {}) {
    config = {
      ...config,
      ...options,
      barColors: { ...config.barColors, ...(options.barColors || {}) }
    }
  },

  show() {
    const bar = ensureBar()
    visible = true
    bar.style.background = config.barColors[0]
    bar.style.boxShadow = `0 0 10px ${config.shadowColor}`
    bar.style.opacity = "1"
    bar.style.width = "80%"
  },

  hide() {
    if (!progressBar || !visible) return
    progressBar.style.width = "100%"

    window.setTimeout(() => {
      if (!progressBar) return
      progressBar.style.opacity = "0"
      progressBar.style.width = "0%"
      visible = false
    }, 200)
  }
}

export default topbar
