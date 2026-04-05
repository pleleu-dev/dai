import gridstack from "../vendor/gridstack"
const GridStack = gridstack.GridStack || gridstack

const DEFAULT_SIZES = {
  kpi_metric:          { w: 1, h: 1 },
  bar_chart:           { w: 2, h: 2 },
  line_chart:          { w: 2, h: 2 },
  pie_chart:           { w: 2, h: 2 },
  data_table:          { w: 4, h: 2 },
  error:               { w: 2, h: 1 },
  clarification:       { w: 2, h: 1 },
  action_confirmation: { w: 2, h: 2 },
  action_result:       { w: 2, h: 1 },
}

const DaiGridStack = {
  mounted() {
    // Parse saved layouts from server-rendered attribute
    this.savedLayouts = JSON.parse(this.el.dataset.gsLayout || "{}")

    // Initialize GridStack
    this.grid = GridStack.init({
      column: 4,
      cellHeight: 80,
      margin: 8,
      float: true,
      animate: true,
      draggable: { cancel: ".no-drag" },
      resizable: { handles: "se" },
      disableOneColumnMode: true,
    }, this.el)

    // Make existing children into widgets
    this.initExistingCards()

    // Observe for new cards added/removed by LiveView stream
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType === 1 && node.dataset.gsCard) {
            this.addCardToGrid(node)
          }
        }
        for (const node of mutation.removedNodes) {
          if (node.nodeType === 1 && node.dataset.gsCard) {
            this.grid.removeWidget(node, false)
          }
        }
      }
    })
    this.observer.observe(this.el, { childList: true })

    // Listen for layout changes (drag/resize)
    this.debounceTimer = null
    this.grid.on("change", (_event, items) => {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = setTimeout(() => {
        const cards = items.map(item => ({
          layout_key: item.el.dataset.layoutKey,
          x: item.x, y: item.y, w: item.w, h: item.h
        })).filter(c => c.layout_key)

        if (cards.length > 0) {
          this.pushEvent("layout_changed", { cards })
        }
      }, 300)
    })
  },

  initExistingCards() {
    const cards = this.el.querySelectorAll("[data-gs-card]")
    this.grid.batchUpdate(true)
    cards.forEach(card => this.addCardToGrid(card))
    this.grid.batchUpdate(false)
  },

  addCardToGrid(el) {
    const layoutKey = el.dataset.layoutKey
    const cardType = el.dataset.cardType
    const saved = this.savedLayouts[layoutKey]
    const defaults = DEFAULT_SIZES[cardType] || { w: 2, h: 2 }

    const opts = saved
      ? { x: saved.x, y: saved.y, w: saved.w, h: saved.h }
      : { w: defaults.w, h: defaults.h, autoPosition: true }

    this.grid.makeWidget(el, opts)
  },

  updated() {},

  destroyed() {
    if (this.observer) this.observer.disconnect()
    if (this.grid) this.grid.destroy(false)
    clearTimeout(this.debounceTimer)
  }
}

export default DaiGridStack
