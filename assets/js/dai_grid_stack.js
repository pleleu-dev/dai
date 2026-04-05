import gridstack from "../vendor/gridstack"
const GridStack = gridstack.GridStack || gridstack

// Using 12-column grid (GridStack default, has built-in CSS)
// Scale: 3 cols = 1/4, 6 cols = 1/2, 9 cols = 3/4, 12 cols = full
const DEFAULT_SIZES = {
  kpi_metric:          { w: 3,  h: 2 },
  bar_chart:           { w: 6,  h: 3 },
  line_chart:          { w: 6,  h: 3 },
  pie_chart:           { w: 6,  h: 3 },
  data_table:          { w: 12, h: 3 },
  error:               { w: 6,  h: 2 },
  clarification:       { w: 6,  h: 2 },
  action_confirmation: { w: 6,  h: 3 },
  action_result:       { w: 6,  h: 2 },
}

const DaiGridStack = {
  mounted() {
    this.savedLayouts = JSON.parse(this.el.dataset.gsLayout || "{}")

    this.grid = GridStack.init({
      column: 12,
      cellHeight: 120,
      margin: 8,
      float: false,
      animate: true,
      draggable: { cancel: ".no-drag" },
      resizable: { handles: "e, se, s" },
      disableOneColumnMode: true,
    }, this.el)

    // Listen for cards pushed from server
    this.handleEvent("add_card", ({ id, html, layout_key, card_type }) => {
      this.addCard(id, html, layout_key, card_type)
    })

    this.handleEvent("remove_card", ({ id }) => {
      this.removeCard(id)
    })

    // Push layout changes back to server on drag/resize
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

    // Hide empty state when cards exist
    this.emptyState = this.el.parentElement?.querySelector("#empty-state")
    this.updateEmptyState()
  },

  addCard(id, html, layoutKey, cardType) {
    const saved = this.savedLayouts[layoutKey]
    const defaults = DEFAULT_SIZES[cardType] || { w: 2, h: 2 }

    const opts = saved
      ? { x: saved.x, y: saved.y, w: saved.w, h: saved.h }
      : { w: defaults.w, h: defaults.h, autoPosition: true }

    // v11 API: addWidget(opts) creates the widget with proper structure.
    // We wrap in batchUpdate to ensure styles are generated after.
    opts.id = id
    opts.content = ""

    const widget = this.grid.addWidget(opts)
    // GridStack v11 doesn't auto-generate height stylesheet in some cases.
    // Force it after adding a widget.
    if (!this._stylesCreated) {
      this.grid._updateStyles(true, this.grid.getRow())
      this._stylesCreated = true
    } else {
      this.grid._updateStyles(false, this.grid.getRow())
    }

    if (widget) {
      widget.dataset.layoutKey = layoutKey
      widget.dataset.cardType = cardType
      widget.dataset.cardId = id
      // Inject server-rendered Phoenix HTML (trusted source)
      const contentDiv = widget.querySelector(".grid-stack-item-content")
      if (contentDiv) contentDiv.innerHTML = html  // safe: server-rendered HTML
    }
    this.updateEmptyState()
  },

  removeCard(id) {
    const el = this.el.querySelector(`[data-card-id="${id}"]`)
    if (el) {
      this.grid.removeWidget(el)
      this.updateEmptyState()
    }
  },

  updateEmptyState() {
    if (this.emptyState) {
      const hasCards = this.el.querySelectorAll(".grid-stack-item").length > 0
      this.emptyState.style.display = hasCards ? "none" : ""
    }
  },

  updated() {},

  destroyed() {
    if (this.grid) this.grid.destroy(false)
    clearTimeout(this.debounceTimer)
  }
}

export default DaiGridStack
