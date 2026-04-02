# Schema Discovery Feature Design

**Date:** 2026-04-02
**Status:** Approved

## Problem

Users land on an empty dashboard with a text input ("Ask anything about your data...") but have zero visibility into what's in the database. They don't know what tables exist, what columns are available, or what questions they can ask. The schema context exists internally and is passed to Claude in the system prompt, but users never see it.

## Solution

A two-part schema discovery feature:

1. **Rich empty state** — onboarding overview with table stats, table list with row counts, and AI-generated suggested queries. Disappears after the first query result appears.
2. **Persistent Schema button** — a "Schema" button in the top nav that opens a right-side drawer panel for ongoing schema exploration. Available at all times, even after results are on screen.

## Architecture

### New module: `Dai.SchemaExplorer`

A GenServer that starts after `Dai.SchemaContext` in the supervision tree. Responsible for enriching raw schema data with row counts and AI-generated suggestions.

**Boot-time flow:**

```
Application starts
  -> SchemaContext.get() returns raw schema text
  -> SchemaExplorer.init()
      -> query row counts (one SELECT count(*) per table, parallel via Task.async_stream)
      -> call Claude API with full schema context -> get 5-8 cross-table suggestions
      -> cache everything in :persistent_term under :dai_schema_explorer
```

**Cached data structure:**

```elixir
%{
  tables: [
    %{
      name: "users",
      columns: [%{name: "id", type: "integer"}, %{name: "name", type: "string"}, ...],
      primary_key: [:id],
      associations: [%{type: :has_many, name: :subscriptions, target: "subscriptions"}, ...],
      row_count: 1_284
    },
    ...
  ],
  suggestions: [
    %{text: "How many active subscribers are there?", tables: ["users", "subscriptions"]},
    %{text: "Revenue by plan this month", tables: ["subscriptions", "invoices", "plans"]},
    ...
  ]
}
```

**On-demand suggestions:**

```elixir
SchemaExplorer.suggest(["users", "invoices"])
# -> Claude API call with just those tables' schema -> returns 3-5 targeted suggestions
```

- Uses the existing `Dai.AI.Client` module (same API key, same Req-based HTTP client)
- Boot suggestions are non-blocking — dashboard renders immediately with schema info and row counts, suggestions populate async
- On-demand suggestions cached in ETS keyed by sorted table combination, evicted on `SchemaContext.reload/0`

### Row counts

- One `SELECT count(*) FROM table` per discovered table, run in parallel via `Task.async_stream`
- Queried using `Dai.Config.repo()` at boot
- Cached in `:persistent_term` alongside table metadata
- If a count query fails for a specific table, show "—" instead of a number

### AI suggestion generation

**Boot-time prompt:**

```
Given this database schema:
#{schema_context}

Generate 5-8 example queries that a non-technical user would find useful.
Prefer queries that span multiple tables. Return JSON array:
[{"text": "human-readable question", "tables": ["table1", "table2"]}]
```

**On-demand prompt:** Same structure but scoped to only the selected tables' schema info (lighter, faster).

**Caching strategy:**

| Data | Storage | Lifecycle |
|---|---|---|
| Boot suggestions | `:persistent_term` | Refreshed on `SchemaContext.reload/0` |
| On-demand suggestions | ETS table | Per-combination, evicted on `SchemaContext.reload/0` |
| Row counts | `:persistent_term` | Refreshed on `SchemaContext.reload/0` |

**Error handling:**

- Boot AI call fails: dashboard loads without suggestions, empty state shows tables and row counts, suggestion section shows "Suggestions unavailable" alert
- On-demand call fails: inline "Couldn't generate suggestions" with retry link
- No new API key or config needed — piggybacks on existing `:ai` config

## UI Design

### Empty state (onboarding)

Renders when no results exist and no query is loading. Replaces the current "Ask anything about your data" placeholder.

**Layout (top to bottom):**

1. **Stats row** — three `stat` cards: table count, column count, relationship count
2. **Tables grid** — 3-column grid of `card` components, each showing table name + `badge` with row count
3. **Suggestions list** — AI-generated suggested queries, each showing the query text + `badge badge-ghost` tags for which tables it spans
4. **Hint text** — "Click to run / Pencil icon to edit / Open Schema to explore tables" using `kbd` components

**Behavior:**

- Click a suggestion → fills the query input and executes immediately
- Click the edit icon (pencil) on a suggestion → fills the query input without executing (user can edit)
- Entire empty state disappears once the first query result streams in

### Schema panel (persistent explorer)

A right-side `drawer drawer-end` triggered by the "Schema" button (`btn btn-ghost btn-sm`) in the top nav.

**State 1 — All tables (panel just opened):**

- Panel header: "Schema Explorer" with ✕ close button
- Table list: each table as a clickable row showing name, column count, relationship count, and row count `badge`

**State 2 — Single table selected:**

- "← All tables" back link (`btn btn-ghost btn-sm`)
- Selected table highlighted as `card bg-primary text-primary-content`
- Columns section: list of column name + type pairs
- Related tables section: `menu` items showing association name + type (has_many, belongs_to), with `→` arrow, clickable to add to focus
- Suggestions section: initially shows any matching boot suggestions, then loads on-demand suggestions (with `loading loading-dots` indicator)

**State 3 — Multi-table focus:**

- "← All tables" back link
- Focused tables shown as `badge badge-primary` pills with ✕ to remove
- Columns per table shown in `collapse` components (collapsible)
- "Also Related" section: tables connected to ANY table in current focus, with "+ add" buttons
- Suggestions regenerated for the table combination

**Interaction flow:**

1. Click "Schema ↗" → panel slides in from right
2. Click a table → drill into columns + associations + suggestions
3. Click a related table → adds to focus, columns collapse, suggestions regenerate
4. Click ✕ on a pill → remove from focus
5. Click "← All tables" → reset to full table list
6. Click a suggestion → executes query, panel stays open

### daisyUI component mapping

| UI Element | daisyUI Component |
|---|---|
| Stats row | `stats` + `stat` (`stat-title`, `stat-value`) |
| Table list items | `card` + `badge` |
| Schema panel | `drawer drawer-end` + `drawer-toggle` |
| Suggestion items | `btn btn-ghost` + `badge badge-ghost` for table tags |
| Table focus pills | `badge badge-primary` with ✕ |
| Column sections | `collapse` |
| Loading indicator | `loading loading-dots` |
| Schema toggle button | `btn btn-ghost btn-sm` |
| Back link | `btn btn-ghost btn-sm` |
| Selected table header | `card bg-primary text-primary-content` |
| Related tables | `menu` + `btn btn-ghost btn-xs` |
| Hint text | `kbd` |
| Error states | `alert` |
| Empty state wrapper | `hero` |

## LiveView integration

### New assigns in `DashboardLive.mount/3`

```elixir
schema_explorer: SchemaExplorer.get(),    # %{tables: [...], suggestions: [...]}
schema_panel_open: false,                  # toggle for right drawer
explorer_focus: [],                        # list of selected table names
explorer_suggestions: [],                  # on-demand suggestions for current focus
explorer_loading: false                    # loading state for on-demand suggestions
```

### New events

| Event | Action |
|---|---|
| `toggle_schema_panel` | Opens/closes the right drawer |
| `select_table` | Adds table to focus, triggers on-demand suggestion fetch |
| `deselect_table` | Removes table from focus, updates suggestions |
| `reset_explorer` | Clears focus, returns to all-tables view |
| `run_suggestion` | Fills input + executes query |
| `edit_suggestion` | Fills input without executing |

### Render helpers in `DashboardComponents`

- `empty_state/1` — full onboarding view (stats, tables, suggestions)
- `schema_panel/1` — right slide-out drawer panel
- `table_list/1` — table listing with counts
- `table_detail/1` — columns + associations for focused table(s)
- `suggestion_list/1` — clickable suggestion items

## Testing

### Unit tests (`Dai.SchemaExplorerTest`)

- `get/0` returns expected structure with tables, row counts, suggestions
- `suggest/1` returns suggestions for given table combination
- Graceful degradation when AI call fails (suggestions empty, tables still present)
- ETS cache hit for repeated `suggest/1` calls (no duplicate API calls)
- `reload/0` clears ETS cache

### LiveView tests

- Empty state renders when no results exist:
  - Stats row shows correct counts
  - All tables listed with row counts
  - Suggestions render with table badges
- Click suggestion executes query (fills input + triggers `query` event)
- Edit suggestion fills input without executing
- Schema panel toggle:
  - `toggle_schema_panel` opens/closes drawer
  - Panel shows all tables on open
- Click-to-explore flow:
  - `select_table` shows columns, associations, and suggestions
  - Clicking related table adds to focus (pills appear)
  - `deselect_table` removes pill and updates suggestions
  - `reset_explorer` returns to all-tables view
- Empty state disappears after first query result streams in
- Schema button remains visible after results appear

### Test approach

Use `Phoenix.LiveViewTest` with mocked `SchemaExplorer` (the GenServer) to avoid real DB and API calls in tests. Test against element IDs/selectors per project conventions.
