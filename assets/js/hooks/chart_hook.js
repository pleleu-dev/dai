import Chart from "chart.js/auto"

const chartInstances = new Map()

function getThemeColors() {
  const style = getComputedStyle(document.documentElement)
  return {
    primary: style.getPropertyValue("--color-primary").trim() || "#570df8",
    secondary: style.getPropertyValue("--color-secondary").trim() || "#f000b8",
    accent: style.getPropertyValue("--color-accent").trim() || "#37cdbe",
    base100: style.getPropertyValue("--color-base-100").trim() || "#ffffff",
    baseContent: style.getPropertyValue("--color-base-content").trim() || "#1f2937",
    neutral: style.getPropertyValue("--color-neutral").trim() || "#3d4451",
  }
}

function getPalette(colors) {
  return [colors.primary, colors.secondary, colors.accent, colors.neutral]
}

function buildConfig(el) {
  const chartType = el.dataset.chartType
  const chartConfig = JSON.parse(el.dataset.chartConfig)
  const colors = getThemeColors()
  const palette = getPalette(colors)

  const baseOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        labels: { color: colors.baseContent }
      },
      tooltip: {
        backgroundColor: colors.neutral,
        titleColor: colors.baseContent,
        bodyColor: colors.baseContent,
      }
    },
  }

  if (chartType === "bar" || chartType === "line") {
    return {
      type: chartType,
      data: {
        labels: chartConfig.labels,
        datasets: [{
          label: chartConfig.dataset_label || "",
          data: chartConfig.values,
          backgroundColor: chartType === "line" ? `color-mix(in oklch, ${colors.primary}, transparent 70%)` : palette.slice(0, chartConfig.values.length),
          borderColor: colors.primary,
          borderWidth: 2,
          fill: chartConfig.fill || false,
          tension: 0.3,
        }]
      },
      options: {
        ...baseOptions,
        scales: {
          x: {
            ticks: { color: colors.baseContent },
            grid: { color: `color-mix(in oklch, ${colors.neutral}, transparent 80%)` },
          },
          y: {
            ticks: { color: colors.baseContent },
            grid: { color: `color-mix(in oklch, ${colors.neutral}, transparent 80%)` },
          }
        }
      }
    }
  }

  if (chartType === "pie") {
    return {
      type: chartConfig.cutout ? "doughnut" : "pie",
      data: {
        labels: chartConfig.labels,
        datasets: [{
          data: chartConfig.values,
          backgroundColor: palette.slice(0, chartConfig.labels.length),
          borderColor: colors.base100,
          borderWidth: 2,
        }]
      },
      options: {
        ...baseOptions,
        cutout: chartConfig.cutout || 0,
      }
    }
  }

  return { type: chartType, data: chartConfig, options: baseOptions }
}

const observer = new MutationObserver((mutations) => {
  for (const mutation of mutations) {
    if (mutation.attributeName === "data-theme") {
      chartInstances.forEach((chart, el) => {
        const newConfig = buildConfig(el)
        chart.data = newConfig.data
        chart.options = newConfig.options
        chart.update()
      })
    }
  }
})

observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] })

const ChartHook = {
  mounted() {
    const canvas = this.el.querySelector("canvas") || this.el
    const config = buildConfig(this.el)
    const chart = new Chart(canvas, config)
    chartInstances.set(this.el, chart)
  },

  destroyed() {
    const chart = chartInstances.get(this.el)
    if (chart) {
      chart.destroy()
      chartInstances.delete(this.el)
    }
  }
}

export default ChartHook
