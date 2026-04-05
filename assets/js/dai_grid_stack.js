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

// Tell GridStack how to render widget content (used by addWidget with 'content' option)
GridStack.renderCB = function(el, widget) {
  const contentEl = el.querySelector(".grid-stack-item-content")
  if (contentEl && widget.content) {
    contentEl.innerHTML = widget.content  // safe: server-rendered Phoenix HTML
  }
}

const DaiGridStack = {
  mounted() {
    this.savedLayouts = JSON.parse(this.el.dataset.gsLayout || "{}")

    this.grid = GridStack.init({
      column: 4,
      cellHeight: 120,
      margin: 8,
      float: true,
      animate: true,
      draggable: { cancel: ".no-drag" },
      resizable: { handles: "se" },
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

    // GridStack.addWidget accepts an options object with 'content'
    // or a DOM element. We use options with 'id' so GridStack creates
    // the proper grid-stack-item > grid-stack-item-content structure.
    opts.id = id
    opts.content = html  // server-rendered Phoenix component HTML (trusted)

    const widget = this.grid.addWidget(opts)
    if (widget) {
      widget.dataset.layoutKey = layoutKey
      widget.dataset.cardType = cardType
    }
    this.updateEmptyState()
  },

  removeCard(id) {
    // GridStack sets gs-id attribute from the 'id' option
    const el = this.el.querySelector(`[gs-id="${id}"]`)
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
