# GridStack Integration Cleanup

## Overview

Clean up the GridStack.js integration to fix rough edges from the initial implementation. The core architecture (GridStack owns grid DOM, LiveView communicates via events) is correct — the problems are implementation details that accumulated across 7 fix commits.

## Problem Summary

The initial GridStack integration hit these issues, each patched incrementally:

1. UMD bundle import required `gridstack.GridStack || gridstack` hack
2. LiveView streams conflicted with GridStack DOM ownership — switched to `push_event` + `phx-update="ignore"`
3. Cards injected via `innerHTML` lose LiveView event bindings — added event delegation
4. GridStack v11 doesn't auto-generate height stylesheet — calling private `_updateStyles` API
5. `addWidget(el)` removed in v11 — switched to `addWidget(opts)` + post-inject HTML
6. Resize handles hidden by default (`ui-resizable-autohide`)

## Scope

### 1. Replace vendored UMD bundle with ESM build

**Current**: `assets/vendor/gridstack.js` is the UMD `gridstack-all.js` (~85KB). Import uses `import gridstack from "../vendor/gridstack"` with a fallback hack.

**Fix**: Download `gridstack-all.mjs` (ESM build) from npm. Vendor as `assets/vendor/gridstack.mjs`.

Import becomes:
```javascript
import { GridStack } from "../vendor/gridstack.mjs"
```

No more `gridstack.GridStack || gridstack` hack. esbuild handles ESM natively.

**How to get the file**: `npm pack gridstack` in a temp dir, extract `dist/gridstack-all.mjs` from the tarball, copy to `assets/vendor/`.

### 2. Stabilize addWidget + stylesheet generation

**Current**: After `addWidget(opts)`, we call `this.grid.cellHeight(this.grid.getCellHeight())` to force stylesheet generation. This is a workaround for GridStack v11 not auto-generating height CSS when the grid starts empty.

**Fix**: Test whether the ESM build handles this differently. If not, try `GridStack.addGrid(el, opts)` factory method (v11 recommended) which may initialize styles properly. If neither works, keep the `cellHeight()` workaround but document it clearly.

### 3. Harden event delegation

**Current**: The DaiGridStack hook has basic `click` and `submit` delegation that calls `pushEvent` for elements with `phx-click`/`phx-submit` attributes.

**Fix**: Handle edge cases:
- Skip elements with `disabled` attribute
- Support `phx-click` on nested elements (already works via `closest()`)
- Verify all card types' interactive elements work:
  - Dismiss button (`phx-click="dismiss"`)
  - Save/bookmark button (`phx-click="save_query"`, `phx-click="save_query_new_folder"`)
  - Retry button (`phx-click="retry"`)
  - Clarification form (`phx-submit="query"`)
  - Action confirm/cancel buttons (`phx-click="confirm_action"`, `phx-click="dismiss"`)

### 4. Verify all card types render correctly

Systematically test each card type through the `push_card` pipeline:

| Card type | Key elements to verify |
|---|---|
| KPI metric | Value display, label, save/dismiss buttons |
| Bar chart | LiveCharts rendering inside GridStack content |
| Line chart | LiveCharts rendering |
| Pie chart | LiveCharts rendering |
| Data table | Scrollable table, column headers, row data |
| Error | Error message, retry button |
| Clarification | Question text, input form, submit |
| Action confirmation | Target table, confirm/cancel buttons |
| Action result | Success/error icon, description |

**Known risk**: LiveCharts uses its own JS hooks. Inside `phx-update="ignore"`, LiveCharts hooks won't be bound by LiveView. If charts don't render, we may need to initialize them manually in the GridStack hook after injecting HTML.

## Files Affected

### Modified
- `assets/js/dai_grid_stack.js` — ESM import, cleaned addWidget flow, hardened event delegation
- `assets/vendor/gridstack.mjs` — replace `gridstack.js` UMD with ESM build

### Deleted
- `assets/vendor/gridstack.js` — replaced by `.mjs` version

### Unchanged
- `assets/js/dai_panel_resizer.js` — works correctly
- `assets/js/app.js` — import path changes from `./gridstack` to `./gridstack.mjs` (or stays same if we keep the filename)
- `assets/css/app.css` — GridStack CSS overrides are correct
- `lib/dai/dashboard_live.ex` — push_card pipeline is correct
- `lib/dai/dashboard_components.ex` — card rendering is correct

## Testing Strategy

### Elixir tests
- Verify `push_card/2` generates correct event payload (id, html, layout_key, card_type)
- Verify `rendered_to_string/1` produces valid HTML for each card type
- Verify event handlers (dismiss, retry, save_query, confirm_action) work when called directly

### Playwright tests
- Navigate to dashboard, submit query, verify card appears
- Click dismiss button on card, verify card removed
- Drag card to new position, verify no JS errors
- Hover card edge, verify resize handle visible
- Submit second query, verify no overlap with first card
- Verify schema explorer and folder panel still work

## Out of Scope

- Layout persistence verification (already tested in unit tests)
- Panel resizer changes (working correctly)
- New card types or features
- Mobile/responsive behavior
