const DaiPanelResizer = {
  mounted() {
    this.direction = this.el.dataset.direction // "horizontal" or "vertical"
    this.name = this.el.dataset.name           // "main_split" or "right_split"
    this.dragging = false

    // Store named references for cleanup
    this._onMouseDown = (e) => this.startDrag(e)
    this._onMouseMove = (e) => this.onDrag(e)
    this._onMouseUp = () => this.stopDrag()
    this._onTouchStart = (e) => this.startDrag(e.touches[0])
    this._onTouchMove = (e) => {
      if (this.dragging) {
        e.preventDefault()
        this.onDrag(e.touches[0])
      }
    }
    this._onTouchEnd = () => this.stopDrag()

    this.el.addEventListener("mousedown", this._onMouseDown)
    document.addEventListener("mousemove", this._onMouseMove)
    document.addEventListener("mouseup", this._onMouseUp)

    this.el.addEventListener("touchstart", this._onTouchStart)
    document.addEventListener("touchmove", this._onTouchMove, { passive: false })
    document.addEventListener("touchend", this._onTouchEnd)
  },

  startDrag(e) {
    this.dragging = true
    this.el.classList.add("active")
    document.body.style.cursor = this.direction === "horizontal" ? "col-resize" : "row-resize"
    document.body.style.userSelect = "none"
  },

  onDrag(e) {
    if (!this.dragging) return

    const container = this.el.parentElement
    const rect = container.getBoundingClientRect()

    let percentage
    if (this.direction === "horizontal") {
      const x = e.clientX - rect.left
      percentage = (x / rect.width) * 100
      // Enforce min widths: left >= 400px, right >= 250px
      const minLeft = (400 / rect.width) * 100
      const maxLeft = ((rect.width - 250) / rect.width) * 100
      percentage = Math.max(minLeft, Math.min(maxLeft, percentage))
    } else {
      const y = e.clientY - rect.top
      percentage = (y / rect.height) * 100
      // Enforce min heights: ~100px each side
      const minTop = (100 / rect.height) * 100
      const maxTop = ((rect.height - 100) / rect.height) * 100
      percentage = Math.max(minTop, Math.min(maxTop, percentage))
    }

    this.applySize(percentage)
    this.lastPercentage = percentage
  },

  stopDrag() {
    if (!this.dragging) return
    this.dragging = false
    this.el.classList.remove("active")
    document.body.style.cursor = ""
    document.body.style.userSelect = ""

    if (this.lastPercentage != null) {
      this.pushEvent("panel_resized", {
        name: this.name,
        size: Math.round(this.lastPercentage)
      })
    }
  },

  applySize(percentage) {
    const container = this.el.parentElement
    const children = Array.from(container.children).filter(c => c !== this.el)
    const first = children[0]
    const second = children[1]

    if (this.direction === "horizontal") {
      first.style.width = `${percentage}%`
      second.style.width = `${100 - percentage}%`
      first.style.flex = "none"
      second.style.flex = "none"
    } else {
      first.style.height = `${percentage}%`
      second.style.height = `${100 - percentage}%`
      first.style.flex = "none"
      second.style.flex = "none"
    }
  },

  destroyed() {
    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)
    document.removeEventListener("touchmove", this._onTouchMove)
    document.removeEventListener("touchend", this._onTouchEnd)
    document.body.style.cursor = ""
    document.body.style.userSelect = ""
  }
}

export default DaiPanelResizer
