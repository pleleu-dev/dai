# Dashboard Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the Dai dashboard to a two-panel layout with GridStack.js drag/resize card grid on the left and combined folders + schema explorer on the right, with resizable panels and server-side layout persistence.

**Architecture:** GridStack.js vendored in `assets/vendor/` handles card drag/resize via a LiveView hook (`DaiGridStack`). A custom `DaiPanelResizer` hook handles resizable panel splits. Two new DB tables (`dai_dashboard_layouts`, `dai_dashboard_preferences`) persist card positions and panel sizes per user. LiveView streams continue to manage card addition/removal while GridStack manages positioning.

**Tech Stack:** Phoenix LiveView 1.1, GridStack.js (vendored ESM), Ecto/Postgres, Tailwind v4 + DaisyUI 5

**Spec:** `docs/superpowers/specs/2026-04-05-dashboard-redesign-design.md`

---

### Task 1: Database schemas and migrations

**Files:**
- Create: `lib/dai/dashboard_layout.ex`
- Create: `lib/dai/dashboard_preferences.ex`
- Create: `priv/repo/migrations/20260405000001_create_dai_dashboard_layouts.exs`
- Create: `priv/repo/migrations/20260405000002_create_dai_dashboard_preferences.exs`
- Test: `test/dai/dashboard_layout_test.exs`
- Test: `test/dai/dashboard_preferences_test.exs`

- [ ] **Step 1: Write migration for `dai_dashboard_layouts`**

Create `priv/repo/migrations/20260405000001_create_dai_dashboard_layouts.exs`:

```elixir
defmodule Dai.Repo.Migrations.CreateDaiDashboardLayouts do
  use Ecto.Migration

  def change do
    create table(:dai_dashboard_layouts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_token, :string, null: false
      add :layout_key, :string, null: false
      add :x, :integer, null: false, default: 0
      add :y, :integer, null: false, default: 0
      add :w, :integer, null: false
      add :h, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:dai_dashboard_layouts, [:user_token, :layout_key])
    create index(:dai_dashboard_layouts, [:user_token])
  end
end
```

- [ ] **Step 2: Write migration for `dai_dashboard_preferences`**

Create `priv/repo/migrations/20260405000002_create_dai_dashboard_preferences.exs`:

```elixir
defmodule Dai.Repo.Migrations.CreateDaiDashboardPreferences do
  use Ecto.Migration

  def change do
    create table(:dai_dashboard_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_token, :string, null: false
      add :panel_sizes, :map, default: %{"main_split" => 75, "right_split" => 50}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:dai_dashboard_preferences, [:user_token])
  end
end
```

- [ ] **Step 3: Run migrations**

Run: `mix ecto.migrate`
Expected: Both tables created successfully.

- [ ] **Step 4: Write Ecto schema for `DashboardLayout`**

Create `lib/dai/dashboard_layout.ex`:

```elixir
defmodule Dai.DashboardLayout do
  @moduledoc "Schema and context for persisting dashboard card grid positions."

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "dai_dashboard_layouts" do
    field :user_token, :string
    field :layout_key, :string
    field :x, :integer, default: 0
    field :y, :integer, default: 0
    field :w, :integer
    field :h, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(layout, attrs) do
    layout
    |> cast(attrs, [:user_token, :layout_key, :x, :y, :w, :h])
    |> validate_required([:user_token, :layout_key, :w, :h])
  end

  defp repo, do: Dai.Config.repo()

  @doc "Generate a layout_key by normalizing and hashing the prompt."
  def layout_key(prompt) do
    prompt
    |> String.trim()
    |> String.downcase()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  @doc "Get all saved layouts for a user, returned as a map of layout_key => %{x, y, w, h}."
  def get_layouts(user_token) do
    __MODULE__
    |> where(user_token: ^user_token)
    |> repo().all()
    |> Map.new(fn l -> {l.layout_key, %{x: l.x, y: l.y, w: l.w, h: l.h}} end)
  end

  @doc "Upsert a card's grid position."
  def save_layout(user_token, layout_key, attrs) do
    case repo().get_by(__MODULE__, user_token: user_token, layout_key: layout_key) do
      nil ->
        %__MODULE__{}
        |> changeset(Map.merge(attrs, %{user_token: user_token, layout_key: layout_key}))
        |> repo().insert()

      existing ->
        existing
        |> changeset(attrs)
        |> repo().update()
    end
  end

  @doc "Batch upsert multiple card positions at once."
  def save_layouts(user_token, cards) when is_list(cards) do
    Enum.each(cards, fn %{"layout_key" => key} = card ->
      save_layout(user_token, key, %{
        x: card["x"],
        y: card["y"],
        w: card["w"],
        h: card["h"]
      })
    end)
  end
end
```

- [ ] **Step 5: Write Ecto schema for `DashboardPreferences`**

Create `lib/dai/dashboard_preferences.ex`:

```elixir
defmodule Dai.DashboardPreferences do
  @moduledoc "Schema and context for persisting dashboard panel sizes."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "dai_dashboard_preferences" do
    field :user_token, :string
    field :panel_sizes, :map, default: %{"main_split" => 75, "right_split" => 50}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(prefs, attrs) do
    prefs
    |> cast(attrs, [:user_token, :panel_sizes])
    |> validate_required([:user_token])
  end

  defp repo, do: Dai.Config.repo()

  @doc "Get preferences for a user, or return defaults."
  def get_preferences(user_token) do
    case repo().get_by(__MODULE__, user_token: user_token) do
      nil -> %{panel_sizes: %{"main_split" => 75, "right_split" => 50}}
      prefs -> %{panel_sizes: prefs.panel_sizes}
    end
  end

  @doc "Upsert panel sizes for a user."
  def save_panel_sizes(user_token, panel_sizes) do
    case repo().get_by(__MODULE__, user_token: user_token) do
      nil ->
        %__MODULE__{}
        |> changeset(%{user_token: user_token, panel_sizes: panel_sizes})
        |> repo().insert()

      existing ->
        existing
        |> changeset(%{panel_sizes: panel_sizes})
        |> repo().update()
    end
  end
end
```

- [ ] **Step 6: Write tests for DashboardLayout**

Create `test/dai/dashboard_layout_test.exs`:

```elixir
defmodule Dai.DashboardLayoutTest do
  use Dai.DataCase, async: true

  alias Dai.DashboardLayout

  describe "layout_key/1" do
    test "normalizes whitespace and case" do
      assert DashboardLayout.layout_key("Show me MRR") ==
               DashboardLayout.layout_key("  show me mrr  ")
    end

    test "different prompts produce different keys" do
      refute DashboardLayout.layout_key("show MRR") ==
               DashboardLayout.layout_key("show churn")
    end

    test "returns a 16-char hex string" do
      key = DashboardLayout.layout_key("test prompt")
      assert String.length(key) == 16
      assert key =~ ~r/^[0-9a-f]{16}$/
    end
  end

  describe "get_layouts/1 and save_layout/3" do
    test "returns empty map when no layouts saved" do
      assert DashboardLayout.get_layouts("user-1") == %{}
    end

    test "saves and retrieves a layout" do
      {:ok, _} = DashboardLayout.save_layout("user-1", "abc123", %{x: 1, y: 2, w: 2, h: 2})

      layouts = DashboardLayout.get_layouts("user-1")
      assert layouts["abc123"] == %{x: 1, y: 2, w: 2, h: 2}
    end

    test "upserts existing layout" do
      {:ok, _} = DashboardLayout.save_layout("user-1", "abc123", %{x: 0, y: 0, w: 1, h: 1})
      {:ok, _} = DashboardLayout.save_layout("user-1", "abc123", %{x: 3, y: 1, w: 2, h: 2})

      layouts = DashboardLayout.get_layouts("user-1")
      assert layouts["abc123"] == %{x: 3, y: 1, w: 2, h: 2}
    end

    test "isolates layouts by user_token" do
      {:ok, _} = DashboardLayout.save_layout("user-1", "key1", %{x: 0, y: 0, w: 1, h: 1})
      {:ok, _} = DashboardLayout.save_layout("user-2", "key2", %{x: 1, y: 1, w: 2, h: 2})

      assert Map.keys(DashboardLayout.get_layouts("user-1")) == ["key1"]
      assert Map.keys(DashboardLayout.get_layouts("user-2")) == ["key2"]
    end
  end

  describe "save_layouts/2" do
    test "batch saves multiple cards" do
      cards = [
        %{"layout_key" => "k1", "x" => 0, "y" => 0, "w" => 1, "h" => 1},
        %{"layout_key" => "k2", "x" => 1, "y" => 0, "w" => 2, "h" => 2}
      ]

      DashboardLayout.save_layouts("user-1", cards)

      layouts = DashboardLayout.get_layouts("user-1")
      assert map_size(layouts) == 2
      assert layouts["k1"] == %{x: 0, y: 0, w: 1, h: 1}
      assert layouts["k2"] == %{x: 1, y: 0, w: 2, h: 2}
    end
  end
end
```

- [ ] **Step 7: Write tests for DashboardPreferences**

Create `test/dai/dashboard_preferences_test.exs`:

```elixir
defmodule Dai.DashboardPreferencesTest do
  use Dai.DataCase, async: true

  alias Dai.DashboardPreferences

  describe "get_preferences/1" do
    test "returns defaults when no preferences saved" do
      prefs = DashboardPreferences.get_preferences("user-1")
      assert prefs.panel_sizes == %{"main_split" => 75, "right_split" => 50}
    end
  end

  describe "save_panel_sizes/2" do
    test "saves and retrieves panel sizes" do
      {:ok, _} = DashboardPreferences.save_panel_sizes("user-1", %{"main_split" => 60, "right_split" => 40})

      prefs = DashboardPreferences.get_preferences("user-1")
      assert prefs.panel_sizes == %{"main_split" => 60, "right_split" => 40}
    end

    test "upserts existing preferences" do
      {:ok, _} = DashboardPreferences.save_panel_sizes("user-1", %{"main_split" => 60, "right_split" => 40})
      {:ok, _} = DashboardPreferences.save_panel_sizes("user-1", %{"main_split" => 80, "right_split" => 30})

      prefs = DashboardPreferences.get_preferences("user-1")
      assert prefs.panel_sizes == %{"main_split" => 80, "right_split" => 30}
    end
  end
end
```

- [ ] **Step 8: Run tests**

Run: `mix test test/dai/dashboard_layout_test.exs test/dai/dashboard_preferences_test.exs`
Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/dai/dashboard_layout.ex lib/dai/dashboard_preferences.ex \
  priv/repo/migrations/20260405000001_create_dai_dashboard_layouts.exs \
  priv/repo/migrations/20260405000002_create_dai_dashboard_preferences.exs \
  test/dai/dashboard_layout_test.exs test/dai/dashboard_preferences_test.exs
git commit -m "feat(layout): add dashboard layout and preferences persistence"
```

---

### Task 2: Add `layout_key` to Result struct

**Files:**
- Modify: `lib/dai/ai/result.ex`
- Modify: `lib/dai/dashboard_live.ex` (the `result_to_card` helper)
- Test: `test/dai/ai/result_test.exs` (if exists, otherwise create)

- [ ] **Step 1: Write test for layout_key on Result**

Create or append to `test/dai/ai/result_test.exs`:

```elixir
defmodule Dai.AI.ResultTest do
  use ExUnit.Case, async: true

  alias Dai.AI.Result

  describe "layout_key field" do
    test "result struct includes layout_key field" do
      result = %Result{
        id: "abc",
        type: :kpi_metric,
        prompt: "show MRR",
        timestamp: DateTime.utc_now(),
        layout_key: "test123"
      }

      assert result.layout_key == "test123"
    end

    test "layout_key defaults to nil" do
      result = %Result{
        id: "abc",
        type: :kpi_metric,
        prompt: "show MRR",
        timestamp: DateTime.utc_now()
      }

      assert result.layout_key == nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/dai/ai/result_test.exs`
Expected: FAIL — `layout_key` not a valid key in Result struct.

- [ ] **Step 3: Add `layout_key` field to Result struct**

In `lib/dai/ai/result.ex`, add `layout_key: String.t() | nil` to the type spec and `layout_key: nil` to defstruct. The type spec (around line 4) should include:

```elixir
layout_key: String.t() | nil,
```

And in the defstruct list (around line 30), add:

```elixir
layout_key: nil,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/dai/ai/result_test.exs`
Expected: PASS

- [ ] **Step 5: Set `layout_key` in `result_to_card` in DashboardLive**

In `lib/dai/dashboard_live.ex`, modify `result_to_card/2` (around line 484-485). Change:

```elixir
defp result_to_card({:ok, result}, _prompt), do: result
defp result_to_card({:error, reason}, prompt), do: Result.error(reason, prompt)
```

To:

```elixir
defp result_to_card({:ok, result}, _prompt) do
  %{result | layout_key: DashboardLayout.layout_key(result.prompt)}
end

defp result_to_card({:error, reason}, prompt) do
  error = Result.error(reason, prompt)
  %{error | layout_key: DashboardLayout.layout_key(prompt)}
end
```

Also add `alias Dai.DashboardLayout` to the aliases at the top of the module (line 5 area).

- [ ] **Step 6: Run full test suite**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/dai/ai/result.ex lib/dai/dashboard_live.ex test/dai/ai/result_test.exs
git commit -m "feat(result): add layout_key field for grid position persistence"
```

---

### Task 3: Vendor GridStack.js

**Files:**
- Create: `assets/vendor/gridstack.js` (vendored ESM build)
- Create: `assets/vendor/gridstack.css` (vendored styles)
- Modify: `assets/css/app.css` (import GridStack CSS + theme overrides)

- [ ] **Step 1: Download GridStack ESM build**

Run:
```bash
curl -L "https://cdn.jsdelivr.net/npm/gridstack@11/dist/gridstack-all.js" -o /home/dev/dai/assets/vendor/gridstack.js
curl -L "https://cdn.jsdelivr.net/npm/gridstack@11/dist/gridstack.min.css" -o /home/dev/dai/assets/vendor/gridstack.css
```

Verify files exist and are non-empty:
```bash
wc -c assets/vendor/gridstack.js assets/vendor/gridstack.css
```

- [ ] **Step 2: Import GridStack CSS in `app.css`**

In `assets/css/app.css`, add after the Tailwind imports (after line 8):

```css
@import "../vendor/gridstack.css";
```

- [ ] **Step 3: Add GridStack theme overrides in `app.css`**

Add at the end of `assets/css/app.css`:

```css
/* GridStack DaisyUI theme integration */
.grid-stack {
  min-height: 160px;
}

.grid-stack-item-content {
  background: transparent;
  border: none;
  inset: 0;
}

.grid-stack > .grid-stack-item > .grid-stack-item-content {
  overflow: visible;
}

.gs-item-content {
  background: transparent;
}

/* Resize handle styling */
.grid-stack > .grid-stack-item > .ui-resizable-se {
  width: 20px;
  height: 20px;
  background: none;
  border-bottom: 2px solid oklch(var(--bc) / 0.2);
  border-right: 2px solid oklch(var(--bc) / 0.2);
  border-radius: 0 0 4px 0;
  bottom: 4px;
  right: 4px;
}

/* Placeholder styling during drag */
.grid-stack > .grid-stack-placeholder > .placeholder-content {
  border: 2px dashed oklch(var(--p) / 0.4);
  background: oklch(var(--p) / 0.05);
  border-radius: 8px;
}
```

- [ ] **Step 4: Verify assets compile**

Run: `mix assets.build`
Expected: No errors. GridStack CSS bundled into output.

- [ ] **Step 5: Commit**

```bash
git add assets/vendor/gridstack.js assets/vendor/gridstack.css assets/css/app.css
git commit -m "chore(deps): vendor gridstack.js for dashboard grid layout"
```

---

### Task 4: DaiPanelResizer LiveView hook

**Files:**
- Create: `assets/js/dai_panel_resizer.js`
- Modify: `assets/js/app.js` (register hook)

- [ ] **Step 1: Create the DaiPanelResizer hook**

Create `assets/js/dai_panel_resizer.js`:

```javascript
import { getAttributeJSON } from "phoenix_live_view"

const DaiPanelResizer = {
  mounted() {
    this.direction = this.el.dataset.direction // "horizontal" or "vertical"
    this.name = this.el.dataset.name           // "main_split" or "right_split"
    this.dragging = false

    this.el.addEventListener("mousedown", (e) => this.startDrag(e))
    document.addEventListener("mousemove", (e) => this.onDrag(e))
    document.addEventListener("mouseup", () => this.stopDrag())

    // Touch support
    this.el.addEventListener("touchstart", (e) => this.startDrag(e.touches[0]))
    document.addEventListener("touchmove", (e) => {
      if (this.dragging) {
        e.preventDefault()
        this.onDrag(e.touches[0])
      }
    }, { passive: false })
    document.addEventListener("touchend", () => this.stopDrag())
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
    document.body.style.cursor = ""
    document.body.style.userSelect = ""
  }
}

export default DaiPanelResizer
```

- [ ] **Step 2: Register hooks in `app.js`**

In `assets/js/app.js`, add imports after the colocated hooks import (after line 25):

```javascript
import DaiPanelResizer from "./dai_panel_resizer"
```

Modify the hooks in LiveSocket initialization (line 31). Change:

```javascript
hooks: {...colocatedHooks},
```

To:

```javascript
hooks: {...colocatedHooks, DaiPanelResizer},
```

- [ ] **Step 3: Add resizer CSS to `app.css`**

Append to `assets/css/app.css`:

```css
/* Panel resizer bars */
.dai-resizer {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background-color 0.15s;
}

.dai-resizer:hover,
.dai-resizer.active {
  background-color: oklch(var(--p) / 0.2);
}

.dai-resizer[data-direction="horizontal"] {
  width: 6px;
  cursor: col-resize;
}

.dai-resizer[data-direction="vertical"] {
  height: 6px;
  cursor: row-resize;
}

.dai-resizer-handle-h {
  width: 2px;
  height: 32px;
  border-radius: 1px;
  background-color: oklch(var(--bc) / 0.3);
}

.dai-resizer-handle-v {
  width: 32px;
  height: 2px;
  border-radius: 1px;
  background-color: oklch(var(--bc) / 0.3);
}
```

- [ ] **Step 4: Verify assets compile**

Run: `mix assets.build`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add assets/js/dai_panel_resizer.js assets/js/app.js assets/css/app.css
git commit -m "feat(hooks): add DaiPanelResizer hook for resizable panels"
```

---

### Task 5: DaiGridStack LiveView hook

**Files:**
- Create: `assets/js/dai_grid_stack.js`
- Modify: `assets/js/app.js` (register hook)

- [ ] **Step 1: Create the DaiGridStack hook**

Create `assets/js/dai_grid_stack.js`:

```javascript
import { GridStack } from "../vendor/gridstack"

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

  updated() {
    // Re-sync if LiveView patches the container
    // GridStack manages positioning, so we just ensure new items are registered
  },

  destroyed() {
    if (this.observer) this.observer.disconnect()
    if (this.grid) this.grid.destroy(false)
    clearTimeout(this.debounceTimer)
  }
}

export default DaiGridStack
```

- [ ] **Step 2: Register hook in `app.js`**

In `assets/js/app.js`, add import after the DaiPanelResizer import:

```javascript
import DaiGridStack from "./dai_grid_stack"
```

Update the hooks object in LiveSocket. Change:

```javascript
hooks: {...colocatedHooks, DaiPanelResizer},
```

To:

```javascript
hooks: {...colocatedHooks, DaiPanelResizer, DaiGridStack},
```

- [ ] **Step 3: Verify assets compile**

Run: `mix assets.build`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add assets/js/dai_grid_stack.js assets/js/app.js
git commit -m "feat(hooks): add DaiGridStack hook for drag/resize card grid"
```

---

### Task 6: Restructure DashboardLive to two-panel layout

This is the core task — rewiring the render function and mount to use the new layout.

**Files:**
- Modify: `lib/dai/dashboard_live.ex`

- [ ] **Step 1: Update imports and aliases in DashboardLive**

In `lib/dai/dashboard_live.ex`, update the aliases and imports at the top of the module. Change lines 4-9:

```elixir
  alias Dai.AI.{ActionExecutor, ActionRegistry, QueryPipeline, Result, ResultAssembler}
  alias Dai.{Folders, Icons, SchemaContext, SchemaExplorer}

  import Dai.DashboardComponents
  import Dai.SchemaExplorerComponents, only: [empty_state: 1, schema_panel: 1]
  import Dai.SidebarComponents, only: [sidebar: 1]
```

To:

```elixir
  alias Dai.AI.{ActionExecutor, ActionRegistry, QueryPipeline, Result, ResultAssembler}
  alias Dai.{DashboardLayout, DashboardPreferences, Folders, Icons, SchemaContext, SchemaExplorer}

  import Dai.DashboardComponents
  import Dai.SchemaExplorerComponents, only: [empty_state: 1, schema_panel_content: 1]
  import Dai.SidebarComponents, only: [folder_panel: 1]
```

- [ ] **Step 2: Rewrite the `render/1` function**

Replace the entire `render/1` function (lines 12-48) with the new two-panel layout:

```elixir
  @impl true
  def render(assigns) do
    ~H"""
    <.dai_wrapper host_layout={@dai_host_layout} flash={@flash}>
      <div class="flex h-full" id="dashboard-panels">
        <%!-- LEFT PANEL: Query input + GridStack card grid --%>
        <div
          style={"width: #{@panel_sizes["main_split"]}%"}
          class="min-w-0 flex flex-col"
        >
          <div class="p-6 pb-0 shrink-0">
            <.query_input form={@form} loading={@loading} />
          </div>
          <.loading_skeleton :if={@loading} />
          <div class="flex-1 min-h-0 overflow-y-auto px-6 pb-6">
            <div
              id="results"
              phx-update="stream"
              phx-hook="DaiGridStack"
              data-gs-layout={Jason.encode!(@saved_layouts)}
              class="grid-stack"
            >
              <.empty_state schema_explorer={@schema_explorer} />
              <div
                :for={{dom_id, result} <- @streams.results}
                id={dom_id}
                data-gs-card
                data-layout-key={result.layout_key}
                data-card-type={result.type}
              >
                <.result_card result={result} folders={@folders} />
              </div>
            </div>
          </div>
        </div>

        <%!-- HORIZONTAL RESIZER --%>
        <div
          id="main-resizer"
          phx-hook="DaiPanelResizer"
          data-direction="horizontal"
          data-name="main_split"
          class="dai-resizer"
        >
          <div class="dai-resizer-handle-h"></div>
        </div>

        <%!-- RIGHT PANEL: Folders + Schema Explorer --%>
        <div
          style={"width: #{100 - @panel_sizes["main_split"]}%"}
          class="min-w-0 flex flex-col border-l border-base-300 bg-base-200/30"
          id="right-panel"
        >
          <%!-- Folders section --%>
          <div style={"height: #{@panel_sizes["right_split"]}%"} class="min-h-0 flex flex-col">
            <.folder_panel
              folders={@folders}
              active_folder_id={@active_folder_id}
              folder_queries={@folder_queries}
            />
          </div>

          <%!-- VERTICAL RESIZER --%>
          <div
            id="right-resizer"
            phx-hook="DaiPanelResizer"
            data-direction="vertical"
            data-name="right_split"
            class="dai-resizer"
          >
            <div class="dai-resizer-handle-v"></div>
          </div>

          <%!-- Schema Explorer section --%>
          <div style={"height: #{100 - @panel_sizes["right_split"]}%"} class="min-h-0 flex flex-col">
            <.schema_panel_content
              schema_explorer={@schema_explorer}
              explorer_focus={@explorer_focus}
              explorer_suggestions={@explorer_suggestions}
              explorer_loading={@explorer_loading}
            />
          </div>
        </div>
      </div>
    </.dai_wrapper>
    """
  end
```

- [ ] **Step 3: Update `mount/3` to load saved layouts and preferences**

Replace mount (lines 165-190) with:

```elixir
  @impl true
  def mount(_params, session, socket) do
    host_layout = Map.get(session, "dai_host_layout", false)
    user_token = Map.get(session, "dai_user_token", generate_fallback_token())

    prefs = DashboardPreferences.get_preferences(user_token)
    saved_layouts = DashboardLayout.get_layouts(user_token)

    {:ok,
     socket
     |> assign(
       loading: false,
       current_prompt: nil,
       task_ref: nil,
       pending_tasks: %{},
       pending_actions: %{},
       dai_host_layout: host_layout,
       user_token: user_token,
       saved_layouts: saved_layouts,
       panel_sizes: prefs.panel_sizes,
       folders: Folders.list_folders(),
       active_folder_id: nil,
       folder_queries: [],
       schema_explorer: SchemaExplorer.get(),
       explorer_focus: [],
       explorer_suggestions: [],
       explorer_loading: false,
       explorer_suggestion_ref: nil
     )
     |> assign(:form, to_form(%{"prompt" => ""}, as: :query))
     |> stream(:results, [])}
  end

  defp generate_fallback_token do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
```

- [ ] **Step 4: Add new event handlers for layout and panel changes**

Add these new handle_event clauses after the existing ones (before `handle_info`):

```elixir
  def handle_event("layout_changed", %{"cards" => cards}, socket) do
    DashboardLayout.save_layouts(socket.assigns.user_token, cards)
    {:noreply, socket}
  end

  def handle_event("panel_resized", %{"name" => name, "size" => size}, socket) do
    panel_sizes = Map.put(socket.assigns.panel_sizes, name, size)
    DashboardPreferences.save_panel_sizes(socket.assigns.user_token, panel_sizes)
    {:noreply, assign(socket, panel_sizes: panel_sizes)}
  end
```

- [ ] **Step 5: Remove old sidebar/schema panel toggle handlers**

Remove these event handlers (they no longer apply):
- `handle_event("toggle_sidebar", ...)` (around line 239-241)
- `handle_event("toggle_schema_panel", ...)` (around line 362-364)

Also remove these assigns from mount since they're no longer needed:
- `sidebar_open: false`
- `schema_panel_open: false`

- [ ] **Step 6: Remove the old `results_grid` component**

Delete the `results_grid/1` private component (lines 143-160) — its content is now inlined in `render/1`.

Remove the schema toggle button block from the old render (the `<div class="flex items-center justify-end mb-2">` block with `#schema-toggle`).

- [ ] **Step 7: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Compiles (may have warnings about removed imports — fix as needed).

- [ ] **Step 8: Commit**

```bash
git add lib/dai/dashboard_live.ex
git commit -m "feat(dashboard): restructure to two-panel layout with GridStack"
```

---

### Task 7: Refactor SidebarComponents into folder panel

The sidebar is no longer a collapsible left sidebar — it becomes the top section of the right panel.

**Files:**
- Modify: `lib/dai/sidebar_components.ex`

- [ ] **Step 1: Replace the `sidebar/1` component with `folder_panel/1`**

The old `sidebar/1` (lines 14-60) had collapse/expand logic. Replace it with a simpler panel component. The core content (`expanded_folder_list`, `folder_query_list`, `save_button`) stays the same — only the outer wrapper changes.

Replace the `sidebar/1` function with:

```elixir
  attr :folders, :list, required: true
  attr :active_folder_id, :string, default: nil
  attr :folder_queries, :list, default: []

  def folder_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex items-center justify-between px-4 py-3 shrink-0 border-b border-base-300">
        <div class="flex items-center gap-2">
          <Icons.folder class="size-4 text-base-content/60" />
          <span class="text-sm font-semibold">Folders</span>
        </div>
        <button
          phx-click={toggle_dropdown("new-folder-input")}
          class="btn btn-ghost btn-xs btn-square"
          aria-label="Create folder"
        >
          <Icons.plus class="size-3.5" />
        </button>
      </div>
      <div id="new-folder-input" class="hidden px-3 py-2 border-b border-base-300">
        <form phx-submit="create_folder" class="flex gap-1">
          <input
            type="text"
            name="name"
            placeholder="Folder name"
            class="input input-xs input-bordered flex-1"
            phx-click-away={hide_dropdown("new-folder-input")}
          />
          <button type="submit" class="btn btn-primary btn-xs">Add</button>
        </form>
      </div>
      <div class="flex-1 overflow-y-auto px-2 py-1">
        <.expanded_folder_list
          folders={@folders}
          active_folder_id={@active_folder_id}
          folder_queries={@folder_queries}
        />
      </div>
    </div>
    """
  end
```

- [ ] **Step 2: Remove `collapsed_folder_list/1` component**

Delete the `collapsed_folder_list/1` component (lines 64-78) — no longer needed since there's no collapsed state.

- [ ] **Step 3: Remove `sidebar_open` references**

Remove the `sidebar_open` attribute from the old `sidebar/1` component. The `expanded_folder_list` no longer needs to check sidebar state.

- [ ] **Step 4: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Compiles. Any warnings about unused functions should be addressed.

- [ ] **Step 5: Commit**

```bash
git add lib/dai/sidebar_components.ex
git commit -m "refactor(sidebar): convert to folder_panel for right panel"
```

---

### Task 8: Refactor SchemaExplorerComponents into inline panel

The schema explorer is no longer a fixed overlay — it becomes the bottom section of the right panel.

**Files:**
- Modify: `lib/dai/schema_explorer_components.ex`

- [ ] **Step 1: Replace `schema_panel/1` with `schema_panel_content/1`**

The old `schema_panel/1` (lines 146-172) was a fixed overlay with a toggle. Replace it with content that flows inside the right panel:

```elixir
  attr :schema_explorer, :map, required: true
  attr :explorer_focus, :list, required: true
  attr :explorer_suggestions, :list, required: true
  attr :explorer_loading, :boolean, required: true

  def schema_panel_content(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex items-center gap-2 px-4 py-3 shrink-0 border-b border-base-300">
        <Icons.table_cells class="size-4 text-base-content/60" />
        <span class="text-sm font-semibold">Schema Explorer</span>
      </div>
      <div class="flex-1 overflow-y-auto px-2 py-1">
        <%= if @explorer_focus == [] do %>
          <.panel_table_list schema_explorer={@schema_explorer} />
        <% else %>
          <.panel_table_detail
            schema_explorer={@schema_explorer}
            explorer_focus={@explorer_focus}
            explorer_suggestions={@explorer_suggestions}
            explorer_loading={@explorer_loading}
          />
        <% end %>
      </div>
    </div>
    """
  end
```

- [ ] **Step 2: Remove old `schema_panel/1` function**

Delete the old `schema_panel/1` (lines 146-172) which had the fixed overlay wrapper and the `schema_panel_open` toggle logic.

- [ ] **Step 3: Update import in DashboardLive**

This was already done in Task 6 Step 1 — verify the import says:

```elixir
import Dai.SchemaExplorerComponents, only: [empty_state: 1, schema_panel_content: 1]
```

- [ ] **Step 4: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Compiles.

- [ ] **Step 5: Commit**

```bash
git add lib/dai/schema_explorer_components.ex
git commit -m "refactor(schema): convert schema panel to inline content component"
```

---

### Task 9: Add GridStack attributes to DashboardComponents cards

Cards need `data-*` attributes for GridStack and `.no-drag` classes on interactive elements.

**Files:**
- Modify: `lib/dai/dashboard_components.ex`

- [ ] **Step 1: Add `layout_key` and `type` attributes to `result_card/1`**

The `result_card/1` component (around line 12) doesn't need GridStack data attributes directly — those go on the stream wrapper div in DashboardLive's render (already done in Task 6). But interactive elements inside cards need `.no-drag` to prevent GridStack from capturing their mouse events.

Add the `no-drag` class to these elements in `result_card/1` and card body components:

In `result_card/1`, add `no-drag` to the save button, dismiss button area:

Find the buttons in `result_card` (around lines 27-43) and add `no-drag` to their parent container. Change the flex container for buttons to include `no-drag`:

```elixir
<div class="flex items-center gap-1 no-drag">
```

- [ ] **Step 2: Add `no-drag` to interactive card elements**

In `clarification_card/1` (around line 175), add `no-drag` to the form:

```elixir
<form phx-submit="query" class="no-drag">
```

In `error_card/1` (around line 155), add `no-drag` to the retry button:

```elixir
<button ... class={["... no-drag"]}>
```

In `action_confirmation_card/1` (around line 198), add `no-drag` to the button row:

```elixir
<div class="flex gap-2 mt-3 no-drag">
```

- [ ] **Step 3: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Compiles.

- [ ] **Step 4: Commit**

```bash
git add lib/dai/dashboard_components.ex
git commit -m "feat(components): add no-drag class to interactive card elements"
```

---

### Task 10: Update router to pass user_token

**Files:**
- Modify: `lib/dai/router.ex`

- [ ] **Step 1: Accept `user_token` in session options**

In `lib/dai/router.ex`, update the `dai_dashboard/2` macro to pass `user_token` through the session. Find the session map construction (around the `live_session` block) and add the user_token:

In the macro body, after extracting `layout` from opts, also extract `user_token`:

```elixir
user_token_getter = Keyword.get(opts, :user_token)
```

And in the session map, add:

```elixir
"dai_user_token" => unquote(user_token_getter)
```

This allows host apps to configure: `dai_dashboard "/dashboard", user_token: &get_user_token/1`

- [ ] **Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Compiles.

- [ ] **Step 3: Commit**

```bash
git add lib/dai/router.ex
git commit -m "feat(router): accept user_token option for layout persistence"
```

---

### Task 11: Migration generator mix task

**Files:**
- Create: `lib/mix/tasks/dai.gen.migrations.ex`

- [ ] **Step 1: Create the mix task**

Create `lib/mix/tasks/dai.gen.migrations.ex`:

```elixir
defmodule Mix.Tasks.Dai.Gen.Migrations do
  @shortdoc "Generates Dai dashboard migrations"
  @moduledoc """
  Generates Ecto migration files for Dai dashboard tables.

      $ mix dai.gen.migrations

  This creates migration files for:
  - `dai_folders` — saved query folders
  - `dai_saved_queries` — saved queries within folders
  - `dai_dashboard_layouts` — card grid positions
  - `dai_dashboard_preferences` — panel sizes and preferences
  """

  use Mix.Task

  import Mix.Generator

  @migrations [
    {"create_dai_folders", "create_dai_folders"},
    {"create_dai_saved_queries", "create_dai_saved_queries"},
    {"create_dai_dashboard_layouts", "create_dai_dashboard_layouts"},
    {"create_dai_dashboard_preferences", "create_dai_dashboard_preferences"}
  ]

  @impl true
  def run(_args) do
    migrations_path = Path.join(["priv", "repo", "migrations"])
    File.mkdir_p!(migrations_path)

    existing = File.ls!(migrations_path)

    for {name, template} <- @migrations do
      if Enum.any?(existing, &String.contains?(&1, name)) do
        Mix.shell().info("Migration #{name} already exists, skipping.")
      else
        timestamp = generate_timestamp()
        filename = "#{timestamp}_#{name}.exs"
        path = Path.join(migrations_path, filename)
        content = migration_content(template)
        create_file(path, content)
        # Small delay to ensure unique timestamps
        Process.sleep(1000)
      end
    end
  end

  defp generate_timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()

    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: "0#{i}"
  defp pad(i), do: "#{i}"

  defp migration_content("create_dai_folders") do
    """
    defmodule MyApp.Repo.Migrations.CreateDaiFolders do
      use Ecto.Migration

      def change do
        create table(:dai_folders, primary_key: false) do
          add :id, :binary_id, primary_key: true
          add :name, :string, null: false
          add :position, :integer

          timestamps(type: :utc_datetime)
        end
      end
    end
    """
  end

  defp migration_content("create_dai_saved_queries") do
    """
    defmodule MyApp.Repo.Migrations.CreateDaiSavedQueries do
      use Ecto.Migration

      def change do
        create table(:dai_saved_queries, primary_key: false) do
          add :id, :binary_id, primary_key: true
          add :folder_id, references(:dai_folders, type: :binary_id, on_delete: :delete_all), null: false
          add :prompt, :text, null: false
          add :title, :string
          add :position, :integer

          timestamps(type: :utc_datetime)
        end

        create index(:dai_saved_queries, [:folder_id])
      end
    end
    """
  end

  defp migration_content("create_dai_dashboard_layouts") do
    """
    defmodule MyApp.Repo.Migrations.CreateDaiDashboardLayouts do
      use Ecto.Migration

      def change do
        create table(:dai_dashboard_layouts, primary_key: false) do
          add :id, :binary_id, primary_key: true
          add :user_token, :string, null: false
          add :layout_key, :string, null: false
          add :x, :integer, null: false, default: 0
          add :y, :integer, null: false, default: 0
          add :w, :integer, null: false
          add :h, :integer, null: false

          timestamps(type: :utc_datetime)
        end

        create unique_index(:dai_dashboard_layouts, [:user_token, :layout_key])
        create index(:dai_dashboard_layouts, [:user_token])
      end
    end
    """
  end

  defp migration_content("create_dai_dashboard_preferences") do
    """
    defmodule MyApp.Repo.Migrations.CreateDaiDashboardPreferences do
      use Ecto.Migration

      def change do
        create table(:dai_dashboard_preferences, primary_key: false) do
          add :id, :binary_id, primary_key: true
          add :user_token, :string, null: false
          add :panel_sizes, :map, default: %{"main_split" => 75, "right_split" => 50}

          timestamps(type: :utc_datetime)
        end

        create unique_index(:dai_dashboard_preferences, [:user_token])
      end
    end
    """
  end
end
```

- [ ] **Step 2: Verify the task runs**

Run: `mix help dai.gen.migrations`
Expected: Shows the task description.

- [ ] **Step 3: Commit**

```bash
git add lib/mix/tasks/dai.gen.migrations.ex
git commit -m "feat(mix): add dai.gen.migrations task for host apps"
```

---

### Task 12: LiveView integration tests

**Files:**
- Modify: existing LiveView test file (find with `Glob`)
- Create: `test/dai/dashboard_live_layout_test.exs` if needed

- [ ] **Step 1: Write test for two-panel layout rendering**

Create `test/dai/dashboard_live_layout_test.exs`:

```elixir
defmodule Dai.DashboardLiveLayoutTest do
  use DaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "two-panel layout" do
    test "renders dashboard-panels container", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#dashboard-panels")
    end

    test "renders GridStack container with hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#results[phx-hook='DaiGridStack']")
    end

    test "renders horizontal resizer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#main-resizer[phx-hook='DaiPanelResizer']")
    end

    test "renders vertical resizer in right panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#right-resizer[phx-hook='DaiPanelResizer']")
    end

    test "renders folder panel in right panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#right-panel")
    end

    test "query input is in left panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#query-form")
    end
  end

  describe "layout persistence events" do
    test "layout_changed event saves card positions", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      cards = [%{"layout_key" => "abc123", "x" => 1, "y" => 0, "w" => 2, "h" => 2}]
      render_hook(view, "layout_changed", %{"cards" => cards})

      # Verify no crash — positions saved silently
      assert has_element?(view, "#dashboard-panels")
    end

    test "panel_resized event saves panel size", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "panel_resized", %{"name" => "main_split", "size" => 60})

      # Verify no crash — panel size saved silently
      assert has_element?(view, "#dashboard-panels")
    end
  end
end
```

- [ ] **Step 2: Run the tests**

Run: `mix test test/dai/dashboard_live_layout_test.exs`
Expected: All tests pass.

- [ ] **Step 3: Run full test suite**

Run: `mix test`
Expected: All tests pass. Fix any failures from removed assigns (sidebar_open, schema_panel_open) in existing tests.

- [ ] **Step 4: Commit**

```bash
git add test/dai/dashboard_live_layout_test.exs
git commit -m "test(dashboard): add layout integration tests"
```

---

### Task 13: Final validation

- [ ] **Step 1: Run precommit checks**

Run: `mix precommit`
Expected: All checks pass (compile warnings, unused deps, format, tests).

- [ ] **Step 2: Fix any formatting issues**

Run: `mix format`

- [ ] **Step 3: Manual smoke test**

Run: `mix dev`

Verify in browser:
1. Two-panel layout renders (left = query + grid, right = folders + schema)
2. Horizontal resizer between panels is draggable
3. Vertical resizer between folders and schema is draggable
4. Submitting a query creates a card in the GridStack grid
5. Cards can be dragged and resized within the grid
6. Card positions persist across page refreshes
7. Panel sizes persist across page refreshes

- [ ] **Step 4: Final commit if any fixes needed**

```bash
git add -u
git commit -m "fix(dashboard): address smoke test findings"
```
