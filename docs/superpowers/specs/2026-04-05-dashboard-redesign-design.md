# Dashboard Redesign: Drag/Resize Grid + Resizable Panels

## Overview

Redesign the Dai dashboard from a static 3-column CSS grid to a two-panel layout with a draggable, resizable card grid (GridStack.js) on the left and a combined folders + schema explorer panel on the right. Panels are resizable via draggable dividers. Card and panel layouts are persisted server-side per user.

## Context

Dai is a Phoenix library mounted into host apps as a git dependency. All changes must be self-contained — no npm dependencies, no host-app configuration burden. The dashboard currently has three panels: a collapsible left sidebar (folders), a center results grid, and a right schema explorer panel.

## Layout Architecture

### Two-panel split

```
┌──────────────────────────────────────────────────────────────┐
│  Navbar (Dai logo)                                           │
├──────────────────────────────────┬──┬─────────────────────────┤
│  Query input                     │  │  📁 Folders             │
│  ┌──────┬──────┬──────┬──────┐   │  │    Revenue Queries (3)  │
│  │ KPI  │ KPI  │ KPI  │ KPI  │   │R │    User Analytics (5)   │
│  ├──────┴──────┼──────┴──────┤   │E │    Churn Analysis (2)   │
│  │  Bar Chart  │ Line Chart  │   │S ├──┬──────────────────────┤
│  │  (2x2)      │ (2x2)       │   │I │R │  🔍 Schema Explorer  │
│  ├─────────────┴─────────────┤   │Z │E │    users (8 cols)     │
│  │  Data Table (4x2)         │   │E │S │    subscriptions (6)  │
│  │                           │   │R │I │    invoices (7)       │
│  └───────────────────────────┘   │  │Z │    events (5)         │
│                                  │  │E │                       │
│  (GridStack 4-col grid)          │  │R │                       │
├──────────────────────────────────┴──┴──┴──────────────────────┤
```

- **Left panel**: query input (pinned top) + scrollable GridStack 4-column card grid
- **Right panel**: folders (top) + schema explorer (bottom), stacked with vertical resizer
- **Horizontal resizer**: draggable bar between left and right panels
- **Constraints**: left panel min 400px, right panel min 250px (no collapse)

### Right panel internal layout

Folders and schema explorer are stacked vertically with a draggable horizontal divider between them. Each section has a minimum height of ~100px. The split ratio is persisted per user.

## GridStack Integration

### Library packaging

- Vendor `gridstack.js` (ESM build, ~45KB gzipped) and `gridstack.css` into `priv/static/vendor/gridstack/`
- Import in Dai's colocated hooks — no npm, no node_modules
- GridStack CSS imported in `app.css` via `@import` from the vendored path
- GridStack's default theme overridden with DaisyUI-compatible CSS variables so cards match the host app's theme

### LiveView stream + GridStack coexistence

LiveView streams handle card addition/removal. GridStack handles card positioning and sizing. They coexist via a `DaiGridStack` hook:

1. **Mount**: hook initializes GridStack on the container div, reads saved layout from `data-gs-layout` JSON attribute, applies positions to existing cards
2. **New card**: LiveView `stream_insert` adds a card DOM element. The hook's `MutationObserver` detects it and calls `grid.makeWidget(el)` with `autoPosition: true` (or saved position if one exists)
3. **Drag/resize**: GridStack `change` event fires. Hook debounces (300ms) and pushes `{card_id, x, y, w, h}` to server via `pushEvent("layout_changed", ...)`
4. **Remove card**: LiveView `stream_delete` removes the DOM element. Hook detects removal via MutationObserver and calls `grid.removeWidget(el, false)`

### Card identity

Cards get a stable identity by normalizing and hashing the prompt text. Normalization: `String.trim() |> String.downcase()`. Then hash: `:crypto.hash(:sha256, normalized) |> Base.encode16() |> binary_part(0, 16)`. This means "show me MRR" and " Show me MRR " map to the same grid position. The existing random `id` field remains for DOM/stream uniqueness, but a new `layout_key` field is used for position persistence.

### Default card sizes (in grid units)

| Card type | Width (w) | Height (h) |
|---|---|---|
| KPI metric | 1 | 1 |
| Bar chart | 2 | 2 |
| Line chart | 2 | 2 |
| Pie chart | 2 | 2 |
| Data table | 4 | 2 |
| Error | 2 | 1 |
| Clarification | 2 | 1 |
| Action confirmation | 2 | 2 |
| Action result | 2 | 1 |

### GridStack configuration

```javascript
GridStack.init({
  column: 4,
  cellHeight: 80,
  margin: 8,
  float: true,
  animate: true,
  draggable: { cancel: '.no-drag' },  // prevent drag on interactive elements
  resizable: { handles: 'se' }         // resize handle bottom-right only
});
```

## LiveView Hooks

### DaiGridStack

Responsibilities:
- Initialize GridStack on `mounted()`
- Set up `MutationObserver` to bridge LiveView stream changes to GridStack
- Listen for GridStack `change` events, debounce, and push layout updates to server
- On `mounted()`, read `data-gs-layout` attribute for saved positions and apply them
- Handle `updated()` callback — re-sync if LiveView patches the container

### DaiPanelResizer

Responsibilities:
- Generic draggable divider hook, parameterized via `data-direction="horizontal|vertical"`
- On `mousedown`: capture pointer, listen for `mousemove` to calculate split percentage
- Apply constraints (min widths/heights) during drag
- On `mouseup`: push final percentage to server via `pushEvent("panel_resized", %{name: ..., size: ...})`
- Reads initial size from `data-initial-size` attribute (server-rendered from saved preferences)

## Data Model

### Table: `dai_dashboard_layouts`

Stores card grid positions. One row per user per card.

| Column | Type | Constraints |
|---|---|---|
| `id` | `binary_id` | PK |
| `user_token` | `string` | not null, indexed |
| `layout_key` | `string` | not null (prompt hash) |
| `x` | `integer` | not null, default 0 |
| `y` | `integer` | not null, default 0 |
| `w` | `integer` | not null |
| `h` | `integer` | not null |
| `inserted_at` | `utc_datetime` | |
| `updated_at` | `utc_datetime` | |

Unique index on `{user_token, layout_key}`.

### Table: `dai_dashboard_preferences`

Stores panel resizer positions and other per-user preferences. One row per user.

| Column | Type | Constraints |
|---|---|---|
| `id` | `binary_id` | PK |
| `user_token` | `string` | not null, unique indexed |
| `panel_sizes` | `map` | default `%{"main_split" => 75, "right_split" => 50}` |
| `inserted_at` | `utc_datetime` | |
| `updated_at` | `utc_datetime` | |

`panel_sizes` stores percentages: `main_split` is the left panel's width percentage, `right_split` is folders' height percentage within the right panel.

### User identification

The host app passes a `user_token` through the LiveView session via `dai_dashboard` route options. If none is provided, the hook generates a random token stored in `localStorage` as a fallback. This allows layout persistence even without host-app authentication.

### Migration delivery

New mix task: `mix dai.gen.migrations` — host apps run this to generate the migration files into their `priv/repo/migrations/` directory. Same pattern as libraries like Oban.

## Modules Affected

### Modified

- **`Dai.DashboardLive`** — new layout structure (two-panel), GridStack container attributes, new event handlers (`layout_changed`, `panel_resized`), load/save layout on mount
- **`Dai.DashboardComponents`** — cards get GridStack-compatible attributes (`data-gs-x`, `data-gs-y`, `data-gs-w`, `data-gs-h`), `.no-drag` class on interactive elements (inputs, buttons)
- **`Dai.SidebarComponents`** — moved into right panel, no longer a standalone sidebar; simplified (no collapse toggle needed)
- **`Dai.SchemaExplorerComponents`** — moved into right panel below folders; schema panel toggle removed (always visible)
- **`Dai.Layouts`** — updated to two-panel structure with resizer bars
- **`Dai.AI.Result`** — new `layout_key` field (prompt hash)
- **`assets/css/app.css`** — import GridStack CSS, override theme variables, resizer bar styles
- **`assets/js/app.js`** — register `DaiGridStack` and `DaiPanelResizer` hooks via colocated pattern

### New

- **`Dai.DashboardLayout`** — Ecto schema + context for `dai_dashboard_layouts` table
- **`Dai.DashboardPreferences`** — Ecto schema + context for `dai_dashboard_preferences` table
- **`Mix.Tasks.Dai.Gen.Migrations`** — mix task to generate migration files for host apps
- **`priv/static/vendor/gridstack/gridstack.js`** — vendored GridStack ESM build
- **`priv/static/vendor/gridstack/gridstack.css`** — vendored GridStack styles
- **`assets/js/hooks/dai_grid_stack.js`** — DaiGridStack LiveView hook
- **`assets/js/hooks/dai_panel_resizer.js`** — DaiPanelResizer LiveView hook

### Removed

- Sidebar collapse toggle behavior (left sidebar no longer exists as a separate panel)
- Schema panel toggle button (schema explorer is always visible in right panel)

## CSS Strategy

- GridStack CSS is scoped to `.grid-stack` class — minimal host app clash risk
- Override GridStack's default card styles to use DaisyUI's `card` classes and theme colors
- Resizer bars styled with Tailwind utility classes, themed via DaisyUI color variables (`base-300`, `base-content`)
- Cards within GridStack use existing `Dai.DashboardComponents` styling (no change to card internals)
- GridStack's `.gs-item` wrapper gets transparent background — visual styling stays on the inner card component

## Edge Cases

- **Empty state**: when no cards exist, show the existing schema explorer hero/empty state in the left panel (centered in the grid area)
- **Cards removed**: when user dismisses a card, layout entry is not deleted — if the same prompt is asked again, it returns to its saved position
- **Window resize**: GridStack handles responsive reflow automatically within its column count. Panel resizer positions are percentage-based, so they scale with window size.
- **Host app without auth**: fallback `user_token` via localStorage ensures layouts persist per-browser even without host-app user identification
