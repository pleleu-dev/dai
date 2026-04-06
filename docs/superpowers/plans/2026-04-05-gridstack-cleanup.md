# GridStack Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the UMD GridStack bundle with ESM modules, remove import hacks, harden event delegation, and verify all card types work.

**Architecture:** GridStack v12 ships individual ESM files in `dist/` (gridstack.js imports gridstack-engine.js, utils.js, etc.). We vendor these files and import directly — esbuild bundles them. The `gridstack-all.js` UMD bundle is deleted. Event delegation is hardened to handle disabled buttons and all card interaction patterns.

**Tech Stack:** GridStack 12.5.0 (ESM), esbuild, Phoenix LiveView hooks

**Spec:** `docs/superpowers/specs/2026-04-05-gridstack-cleanup-design.md`

---

### Task 1: Replace UMD bundle with ESM modules

**Files:**
- Create: `assets/vendor/gridstack/gridstack.js` (and all ESM deps)
- Delete: `assets/vendor/gridstack.js` (old UMD bundle)
- Delete: `assets/vendor/gridstack.css` (moved into gridstack/ dir)
- Modify: `assets/js/dai_grid_stack.js` (import path)
- Modify: `assets/css/app.css` (CSS import path)

- [ ] **Step 1: Extract ESM files from npm package**

```bash
cd /tmp/gs-check
tar xf gridstack-*.tgz
# Copy all ESM JS files from dist/
mkdir -p /home/dev/dai/assets/vendor/gridstack
cp package/dist/gridstack.js \
   package/dist/gridstack-engine.js \
   package/dist/utils.js \
   package/dist/types.js \
   package/dist/dd-base-impl.js \
   package/dist/dd-draggable.js \
   package/dist/dd-droppable.js \
   package/dist/dd-element.js \
   package/dist/dd-gridstack.js \
   package/dist/dd-manager.js \
   package/dist/dd-resizable.js \
   package/dist/dd-resizable-handle.js \
   package/dist/dd-touch.js \
   /home/dev/dai/assets/vendor/gridstack/
# Copy CSS
cp package/dist/gridstack.min.css /home/dev/dai/assets/vendor/gridstack/gridstack.css
```

- [ ] **Step 2: Delete old UMD bundle and CSS**

```bash
rm /home/dev/dai/assets/vendor/gridstack.js
rm /home/dev/dai/assets/vendor/gridstack.css
```

- [ ] **Step 3: Update import in `dai_grid_stack.js`**

Change lines 1-2 from:

```javascript
import gridstack from "../vendor/gridstack"
const GridStack = gridstack.GridStack || gridstack
```

To:

```javascript
import { GridStack } from "../vendor/gridstack/gridstack.js"
```

- [ ] **Step 4: Update CSS import in `app.css`**

Change line 10 from:

```css
@import "../vendor/gridstack.css";
```

To:

```css
@import "../vendor/gridstack/gridstack.css";
```

- [ ] **Step 5: Verify build succeeds**

Run: `mix assets.build`
Expected: No errors, esbuild resolves all ESM imports.

- [ ] **Step 6: Verify in browser — no JS errors**

Open http://localhost:4000, check browser console for errors.
The GridStack grid should initialize without the UMD import hack.

- [ ] **Step 7: Commit**

```bash
git add assets/vendor/gridstack/ assets/js/dai_grid_stack.js assets/css/app.css
git rm assets/vendor/gridstack.js assets/vendor/gridstack.css
git commit -m "refactor(gridstack): replace UMD bundle with ESM modules"
```

---

### Task 2: Stabilize addWidget and stylesheet generation

**Files:**
- Modify: `assets/js/dai_grid_stack.js`

- [ ] **Step 1: Test if ESM build auto-generates height styles**

Open http://localhost:4000, submit a query, then run in browser console:

```javascript
document.querySelectorAll('style').length
```

If > 0 and the card has proper height, the ESM build fixed the issue and we can remove the `cellHeight()` workaround. If still 0, proceed to step 2.

- [ ] **Step 2: If styles still missing, keep workaround with clear comment**

In `assets/js/dai_grid_stack.js`, the `addCard` method currently has:

```javascript
const widget = this.grid.addWidget(opts)
// Force GridStack to regenerate its height stylesheet via public API
this.grid.cellHeight(this.grid.getCellHeight())
```

If the ESM build fixed auto-generation, remove the `cellHeight` line. If not, keep it with this comment:

```javascript
const widget = this.grid.addWidget(opts)
// GridStack v12 doesn't auto-generate its height stylesheet when widgets
// are added to an initially empty grid. Re-setting cellHeight forces it.
this.grid.cellHeight(this.grid.getCellHeight())
```

- [ ] **Step 3: Verify card dimensions are correct**

In browser console after submitting a query:

```javascript
const item = document.querySelector('.grid-stack-item')
console.log('offsetW:', item.offsetWidth, 'offsetH:', item.offsetHeight)
// Expected: offsetW > 200, offsetH > 100
```

- [ ] **Step 4: Commit if changes were made**

```bash
git add assets/js/dai_grid_stack.js
git commit -m "refactor(gridstack): stabilize addWidget stylesheet generation"
```

---

### Task 3: Harden event delegation

**Files:**
- Modify: `assets/js/dai_grid_stack.js`

- [ ] **Step 1: Update click delegation to skip disabled elements**

In `assets/js/dai_grid_stack.js`, replace the click event listener (currently at the `// Event delegation` section) with:

```javascript
    // Event delegation: phx-click/phx-submit inside phx-update="ignore"
    // won't be bound by LiveView, so we handle them here.
    this.el.addEventListener("click", (e) => {
      const target = e.target.closest("[phx-click]")
      if (!target) return
      if (target.disabled || target.getAttribute("disabled") !== null) return
      e.preventDefault()
      e.stopPropagation()
      const event = target.getAttribute("phx-click")
      const values = {}
      for (const attr of target.attributes) {
        if (attr.name.startsWith("phx-value-")) {
          values[attr.name.replace("phx-value-", "")] = attr.value
        }
      }
      this.pushEvent(event, values)
    })

    this.el.addEventListener("submit", (e) => {
      const form = e.target.closest("[phx-submit]")
      if (!form) return
      e.preventDefault()
      const event = form.getAttribute("phx-submit")
      const formData = new FormData(form)
      this.pushEvent(event, Object.fromEntries(formData))
      form.reset()
    })
```

Changes from current code:
- Added `disabled` check (skip disabled buttons)
- Added `form.reset()` after submit (clear clarification input)

- [ ] **Step 2: Verify build**

Run: `mix assets.build`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add assets/js/dai_grid_stack.js
git commit -m "fix(gridstack): harden event delegation with disabled check and form reset"
```

---

### Task 4: Verify all card types with Elixir tests

**Files:**
- Create: `test/dai/push_card_test.exs`

- [ ] **Step 1: Write tests for push_card HTML generation**

Create `test/dai/push_card_test.exs`:

```elixir
defmodule Dai.PushCardTest do
  use ExUnit.Case, async: true

  alias Dai.AI.Result

  @card_types ~w(kpi_metric bar_chart line_chart pie_chart data_table error clarification action_confirmation action_result)a

  describe "rendered_to_string/1 for result_card" do
    test "renders error card with retry button" do
      result = %Result{
        id: "test1",
        type: :error,
        prompt: "test query",
        timestamp: DateTime.utc_now(),
        error: "Something went wrong",
        layout_key: "abc123"
      }

      html = render_card(result)

      assert html =~ "Something went wrong"
      assert html =~ ~s(phx-click="retry")
      assert html =~ ~s(phx-click="dismiss")
      assert html =~ ~s(phx-value-id="test1")
    end

    test "renders kpi_metric card with value" do
      result = %Result{
        id: "test2",
        type: :kpi_metric,
        prompt: "count users",
        timestamp: DateTime.utc_now(),
        title: "Total Users",
        description: "Count of users",
        data: %{columns: ["count"], rows: [%{"count" => 200}]},
        config: %{"format" => "number", "label" => "Users"},
        layout_key: "def456"
      }

      html = render_card(result)

      assert html =~ "200"
      assert html =~ "Total Users"
      assert html =~ ~s(phx-click="dismiss")
    end

    test "renders data_table card with columns and rows" do
      result = %Result{
        id: "test3",
        type: :data_table,
        prompt: "list users",
        timestamp: DateTime.utc_now(),
        title: "Users",
        data: %{
          columns: ["name", "email"],
          rows: [
            %{"name" => "Alice", "email" => "alice@example.com"},
            %{"name" => "Bob", "email" => "bob@example.com"}
          ]
        },
        config: %{},
        layout_key: "ghi789"
      }

      html = render_card(result)

      assert html =~ "Alice"
      assert html =~ "bob@example.com"
      assert html =~ "name"
      assert html =~ "email"
    end

    test "renders clarification card with form" do
      result = %Result{
        id: "test4",
        type: :clarification,
        prompt: "show data",
        timestamp: DateTime.utc_now(),
        question: "Which table do you mean?",
        layout_key: "jkl012"
      }

      html = render_card(result)

      assert html =~ "Which table do you mean?"
      assert html =~ ~s(phx-submit="query")
      assert html =~ ~s(name="prompt")
    end

    test "all rendered cards contain dismiss button" do
      results = [
        %Result{id: "e1", type: :error, prompt: "p", timestamp: DateTime.utc_now(), error: "err", layout_key: "a"},
        %Result{id: "k1", type: :kpi_metric, prompt: "p", timestamp: DateTime.utc_now(), title: "T",
                data: %{columns: ["v"], rows: [%{"v" => 1}]}, config: %{}, layout_key: "b"},
        %Result{id: "d1", type: :data_table, prompt: "p", timestamp: DateTime.utc_now(), title: "T",
                data: %{columns: ["c"], rows: [%{"c" => 1}]}, config: %{}, layout_key: "c"},
        %Result{id: "c1", type: :clarification, prompt: "p", timestamp: DateTime.utc_now(),
                question: "Q?", layout_key: "d"}
      ]

      for result <- results do
        html = render_card(result)
        assert html =~ ~s(phx-click="dismiss"), "#{result.type} card missing dismiss button"
        assert html =~ ~s(phx-value-id="#{result.id}"), "#{result.type} card missing phx-value-id"
      end
    end
  end

  defp render_card(result) do
    assigns = %{result: result, folders: []}

    Dai.DashboardComponents.result_card(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
```

- [ ] **Step 2: Run tests**

Run: `mix test test/dai/push_card_test.exs`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/dai/push_card_test.exs
git commit -m "test(cards): add push_card HTML rendering tests for all card types"
```

---

### Task 5: Playwright end-to-end verification

**Files:** None (manual browser testing via Playwright MCP)

- [ ] **Step 1: Navigate and check for errors**

Navigate to http://localhost:4000. Check browser console — expect 0 errors.

- [ ] **Step 2: Submit a query, verify card appears**

Type "how many users?" and submit. Wait for result. Verify:
- Card appears in grid with proper width/height
- No JS console errors
- Empty state hides when card appears

- [ ] **Step 3: Verify card buttons work via event delegation**

Click the dismiss (X) button on the card. Verify:
- Card is removed from the grid
- Empty state reappears
- No JS errors

- [ ] **Step 4: Submit two queries, verify no overlap**

Submit "how many users?" then "list all plans". Verify:
- Both cards appear
- Cards do not overlap (float: false pushes second card down)
- Both cards have proper dimensions

- [ ] **Step 5: Verify drag works**

Programmatically test via browser console:

```javascript
const gs = document.querySelector('.grid-stack').gridstack
const items = gs.engine.nodes
gs.update(items[0].el, {x: 6, y: 0})
// Card should move to the right half
```

- [ ] **Step 6: Verify resize handle visible**

Hover over a card edge. Verify resize handle (grip icon) is visible, not hidden.

- [ ] **Step 7: Verify schema explorer and folders still work**

Click a table in Schema Explorer — detail view should appear. Click "+" in Folders — should create a new folder.

---

### Task 6: Final validation

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 2: Run precommit**

Run: `mix precommit`
Expected: No warnings, all tests pass, formatting correct.

- [ ] **Step 3: Verify assets build cleanly**

Run: `mix assets.build`
Expected: No errors. Bundle size should be similar or smaller than before (~415-420KB).
