# Dai Core MVP — Design Spec

> First sub-project of the Dai AI Dashboard. Delivers the end-to-end pipeline: user types a natural-language question, the system generates SQL via Claude, executes it, and renders the result as a card in a dashboard grid.

---

## Scope

**In scope:**

- Chat-to-chart pipeline (prompt -> Claude -> SQL -> visualization)
- 5 visualization components: KPI metric, bar chart, line chart, pie chart, data table
- Dashboard grid UI — input at top, results accumulate as cards
- Schema context system — Mix task + GenServer cache
- SaaS analytics sample dataset with seed data
- Chart.js integration via LiveView hooks with theme-aware rendering
- Light/dark theme toggle (inherits host theme via DaisyUI CSS variables)
- Inline error cards for pipeline failures
- Clarification flow (Claude asks follow-up questions)

**Out of scope (future sub-projects):**

- Authentication, multi-tenancy, row-level scoping
- Query audit log
- Multi-turn conversation
- Query history, caching, rate limiting
- Export (CSV, PNG)
- Additional chart types
- Quick actions
- Dashboards, sharing, scheduling

---

## Data Model

### Ecto Schemas (SaaS analytics sample dataset)

All schemas live under `Dai.Analytics` context in `lib/dai/analytics/`.

#### `users`

| Column | Type | Notes |
|---|---|---|
| id | integer | PK |
| name | string | |
| email | string | unique |
| role | string | admin, manager, member |
| org_name | string | one of 5 sample orgs |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

#### `plans`

| Column | Type | Notes |
|---|---|---|
| id | integer | PK |
| name | string | Free, Starter, Pro, Enterprise |
| price_monthly | integer | cents (0, 2900, 7900, 19900) |
| tier | string | free, starter, pro, enterprise |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

#### `subscriptions`

| Column | Type | Notes |
|---|---|---|
| id | integer | PK |
| user_id | integer | FK -> users |
| plan_id | integer | FK -> plans |
| status | string | active, cancelled, past_due |
| started_at | utc_datetime | |
| cancelled_at | utc_datetime | nullable |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

#### `invoices`

| Column | Type | Notes |
|---|---|---|
| id | integer | PK |
| subscription_id | integer | FK -> subscriptions |
| amount_cents | integer | matches plan price +/- variation |
| status | string | paid, pending, failed |
| due_date | date | |
| paid_at | utc_datetime | nullable |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

#### `events`

| Column | Type | Notes |
|---|---|---|
| id | integer | PK |
| user_id | integer | FK -> users |
| name | string | page_view, signup, upgrade, downgrade, feature_used |
| properties | map | JSON metadata |
| inserted_at | utc_datetime | |

#### `features`

| Column | Type | Notes |
|---|---|---|
| id | integer | PK |
| name | string | feature name |
| plan_id | integer | FK -> plans |
| enabled | boolean | |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

### Seed Data

`priv/repo/seeds.exs` generates deterministic sample data using a fixed `:rand` seed.

| Table | Rows | Notes |
|---|---|---|
| plans | 4 | Free, Starter ($29), Pro ($79), Enterprise ($199) |
| users | 200 | Spread across 5 org_names, mixed roles |
| subscriptions | 200 | 1:1 with users; ~70% active, ~20% cancelled, ~10% past_due |
| invoices | ~2,400 | ~12 months of monthly invoices per active subscription |
| events | ~5,000 | 5 event types, spread over 90 days, weighted toward business hours |
| features | 20 | 5 features per plan tier |

Dates span the last 12 months from the current date. Seeds run via `mix setup`.

---

## Schema Context System

### Mix Task: `mix gen_schema_context`

Module: `Mix.Tasks.GenSchemaContext` in `lib/mix/tasks/gen_schema_context.ex`.

- Discovers all modules that export `__schema__/1`
- For each schema, extracts: source table, fields + Ecto types, primary key, associations (type, related module, foreign key)
- Writes structured JSON to `priv/ai/schema_context.json`

### GenServer: `Dai.SchemaContext`

Module: `lib/dai/schema_context.ex`.

- Started in application supervision tree
- `init/1` — loads and parses `priv/ai/schema_context.json`, formats into a prompt-ready string
- `Dai.SchemaContext.get/0` — returns the cached schema context string
- `Dai.SchemaContext.reload/0` — re-reads the JSON file (dev convenience)

### Mix Aliases

- `ecto.migrate` triggers `gen_schema_context` after migration
- `phx.server` triggers `gen_schema_context` before server start

---

## AI Query Pipeline

### Architecture

Approach: LiveView + Pipeline Module. The pipeline is a pure function chain — easy to test independently. The LiveView's only job is: take user input, call the pipeline in an async task, render the result card.

### Module: `Dai.AI.QueryPipeline`

Single public function: `run(prompt, schema_context)` -> `{:ok, %Result{}}` | `{:error, reason}`.

Chains four steps internally, short-circuiting on first error:

```
prompt + schema_context
  -> Dai.AI.Client.generate_plan/2
  -> Dai.AI.PlanValidator.validate/1
  -> Dai.AI.SqlExecutor.execute/1
  -> Dai.AI.ResultAssembler.assemble/2
```

### Step 1: `Dai.AI.Client`

Module: `lib/dai/ai/client.ex`.

- Sends POST to Claude Messages API via Req
- Model: `claude-sonnet-4-6` (configurable via `AI_MODEL` env var)
- API key from `ANTHROPIC_API_KEY` env var
- System prompt + user prompt in messages array
- Parses JSON from response content
- Returns `{:ok, plan_map}` or `{:error, :api_error | :invalid_json}`

### Step 2: `Dai.AI.PlanValidator`

Module: `lib/dai/ai/plan_validator.ex`.

- Validates the parsed plan map
- **Keyword blocklist** — lowercased SQL scanned for: INSERT, UPDATE, DELETE, DROP, TRUNCATE, ALTER, CREATE, GRANT, REVOKE, EXEC, EXECUTE. Rejects on match.
- **LIMIT enforcement** — appends `LIMIT 500` (data_table) or `LIMIT 50` (charts/kpi) if no LIMIT present
- **Component validation** — must be one of: `kpi_metric`, `bar_chart`, `line_chart`, `pie_chart`, `data_table`
- **Clarification passthrough** — if `needs_clarification: true`, passes through without SQL validation
- Returns `{:ok, validated_plan}` or `{:error, :forbidden_sql | :invalid_component}`

### Step 3: `Dai.AI.SqlExecutor`

Module: `lib/dai/ai/sql_executor.ex`.

- Runs SQL via `Ecto.Adapters.SQL.query(Dai.Repo, sql)`
- Converts `%Postgrex.Result{columns: cols, rows: rows}` into `%{columns: [String.t()], rows: [map()]}`
- Returns `{:ok, query_result}` or `{:error, :query_failed}`

### Step 4: `Dai.AI.ResultAssembler`

Module: `lib/dai/ai/result_assembler.ex`.

- Takes the validated plan and query result
- Builds `%Dai.AI.Result{}` struct
- For clarification responses, builds a result with `type: :clarification`

### Struct: `Dai.AI.Result`

Module: `lib/dai/ai/result.ex`.

```elixir
defstruct [
  :id,          # unique string (8-char random)
  :type,        # :kpi_metric | :bar_chart | :line_chart | :pie_chart | :data_table | :clarification | :error
  :title,       # string
  :description, # string
  :config,      # map (axis labels, format, etc.)
  :data,        # %{columns: [...], rows: [...]}
  :prompt,      # original user prompt
  :error,       # error message (only for :error type)
  :question,    # clarification question (only for :clarification type)
  :timestamp    # DateTime
]
```

---

## System Prompt

Three sections:

### Section 1 — Role & output contract

Instructs Claude to respond with only a valid JSON object. No markdown, no explanation, no wrapping. Read-only SELECT queries only.

### Section 2 — Schema context

The formatted schema string from `Dai.SchemaContext.get/0`. Lists each table with columns, types, primary keys, and associations.

### Section 3 — Decision rules

| Data shape | Component |
|---|---|
| Single scalar value (count, sum, avg) | `kpi_metric` |
| Time series (date/datetime + numeric) | `line_chart` |
| Categorical comparison (label + numeric) | `bar_chart` |
| Part-of-whole proportions (< 8 categories) | `pie_chart` |
| Multiple columns or raw rows | `data_table` |

Additional rules:
- All queries must be read-only SELECT
- Always include LIMIT (50 for charts, 500 for tables)
- If prompt is ambiguous, return `{"needs_clarification": true, "question": "..."}`

### Few-shot examples

3 examples using the actual SaaS schema:

1. **KPI** — "how many active users?" -> `SELECT COUNT(*) ...` with `kpi_metric` component
2. **Chart** — "revenue by plan this month" -> `SELECT p.name, SUM(...) ...` with `bar_chart` component
3. **Table** — "show recent failed invoices" -> `SELECT ... ORDER BY ...` with `data_table` component

Module: `Dai.AI.SystemPrompt` in `lib/dai/ai/system_prompt.ex`. Single function `build(schema_context)` returns the full system prompt string.

---

## Response JSON Contract

### Query result

```json
{
  "title": "string — human-readable title for the card",
  "description": "string — one-line explanation of the result",
  "sql": "SELECT ... — the generated SQL query",
  "component": "kpi_metric | bar_chart | line_chart | pie_chart | data_table",
  "config": {}
}
```

### Config by component type

**kpi_metric:**
```json
{"label": "Active Users", "format": "number|currency|percent"}
```

**bar_chart:**
```json
{"x_axis": "column_name", "y_axis": "column_name", "orientation": "vertical|horizontal"}
```

**line_chart:**
```json
{"x_axis": "column_name", "y_axis": "column_name", "fill": true|false}
```

**pie_chart:**
```json
{"label_field": "column_name", "value_field": "column_name"}
```

**data_table:**
```json
{"columns": ["col1", "col2", "col3"]}
```

### Clarification

```json
{
  "needs_clarification": true,
  "question": "string — follow-up question for the user"
}
```

---

## LiveView: `DaiWeb.DashboardLive`

### Route

`GET /` — replaces current `PageController` route.

```elixir
scope "/", DaiWeb do
  pipe_through :browser
  live "/", DashboardLive
end
```

### Assigns

| Assign | Type | Description |
|---|---|---|
| `results` | stream | Stream of `%Dai.AI.Result{}` — cards in the grid |
| `loading` | boolean | True while async task is running |
| `form` | Phoenix.HTML.Form | Query input form |
| `current_prompt` | string or nil | The prompt currently being processed (used for error cards and retry) |
| `task_ref` | reference or nil | Ref of the in-flight async task |

### Events

| Event | Trigger | Handler |
|---|---|---|
| `"query"` | Form submit | Spawns async task with `QueryPipeline.run/2` |
| `"dismiss"` | Click X on card | `stream_delete` the result from stream |
| `"retry"` | Click retry on error card | Re-runs the original prompt |
| `"toggle-theme"` | Click theme button | Toggles `data-theme`, persists to session |

### Async Pattern

```elixir
def handle_event("query", %{"prompt" => prompt}, socket) do
  task = Task.async(fn -> QueryPipeline.run(prompt, SchemaContext.get()) end)
  {:noreply, assign(socket, loading: true, task_ref: task.ref, current_prompt: prompt)}
end

def handle_info({ref, {:ok, result}}, socket) when socket.assigns.task_ref == ref do
  Process.demonitor(ref, [:flush])
  {:noreply, socket |> stream_insert(:results, result, at: 0) |> assign(loading: false)}
end

def handle_info({ref, {:error, reason}}, socket) when socket.assigns.task_ref == ref do
  Process.demonitor(ref, [:flush])
  error_result = Result.error(reason, socket.assigns.current_prompt)
  {:noreply, socket |> stream_insert(:results, error_result, at: 0) |> assign(loading: false)}
end
```

### Template Structure

```
<Layouts.app flash={@flash}>
  <!-- Nav: logo + light/dark toggle -->
  <!-- Query input bar (top, full width) -->
  <!-- Loading indicator (skeleton card, visible when @loading) -->
  <!-- Results grid: CSS grid, responsive 1-3 columns -->
  <!--   phx-update="stream", id="results" -->
  <!--   Each card dispatches by result.type -->
</Layouts.app>
```

---

## Dashboard Components

Module: `DaiWeb.DashboardComponents` in `lib/dai_web/components/dashboard_components.ex`.

### `result_card/1`

Wrapper component. Takes a `%Result{}` assign and dispatches to the inner component based on `type`. Renders a card container with title, description, and a dismiss button.

### `kpi_metric/1`

Large number display. Reads `config.format` to apply formatting:
- `number` — comma-separated integer
- `currency` — `$X,XXX.XX`
- `percent` — `X.X%`

### `bar_chart/1`

Renders a `<canvas>` element with:
- `phx-hook="ChartHook"`
- `phx-update="ignore"`
- `data-chart-type="bar"`
- `data-chart-config={Jason.encode!(config_with_data)}`

### `line_chart/1`

Same pattern as bar_chart, `data-chart-type="line"`.

### `pie_chart/1`

Same pattern, `data-chart-type="pie"`. Switches to donut (cutout: 50%) when > 4 segments.

### `data_table/1`

Pure HTML table. Tailwind-styled with:
- Zebra striping
- Horizontal scroll wrapper for wide tables
- Column headers from `config.columns` or `data.columns`

### `error_card/1`

Styled with error/warning colors. Shows error message and a retry button that fires `phx-click="retry"` with the original prompt.

### `clarification_card/1`

Shows Claude's question. Includes a text input so the user can respond directly from the card (fires `"query"` event with the response).

---

## Chart.js Hook

File: `assets/js/hooks/chart_hook.js`.

### Lifecycle

- **`mounted()`** — reads `data-chart-type` and `data-chart-config` from element. Reads DaisyUI CSS variables (`--b1`, `--bc`, `--p`, `--s`, `--a`, `--n`) from `getComputedStyle(document.documentElement)`. Creates `new Chart(canvas, chartConfig)` with resolved colors.
- **`destroyed()`** — calls `chart.destroy()` to prevent memory leaks.

### Theme Sync

A `MutationObserver` on `document.documentElement` watches the `data-theme` attribute. On change, iterates all mounted chart instances, re-reads CSS variables, updates chart colors, and calls `chart.update()`. No server round-trip needed.

### Registration

Registered via Phoenix's colocated hooks pattern. The hook file at `assets/js/hooks/chart_hook.js` is discovered by `app.js` through the `phoenix-colocated/dai` import, which auto-collects hooks and passes them to `LiveSocket`. No manual import or hook map entry needed — just export the hook as default from the file.

---

## Theme System

### Approach

The dashboard inherits the host application's theme via DaisyUI CSS variables. No custom theme definitions — the app works with whatever `data-theme` is set on the `<html>` element.

### Light/Dark Toggle

A convenience toggle in the nav bar for standalone development:
- Toggles `data-theme` between `light` and `dark`
- Persists selection to `localStorage` via a small JS snippet
- Persists to server session via `phx-click="toggle-theme"` event
- Root layout reads theme from session and sets `data-theme` attribute server-side (no flash of wrong theme)

### Chart Color Resolution

Charts read these DaisyUI CSS variables at render time:
- `--p` (primary) — main data color
- `--s` (secondary) — secondary series
- `--a` (accent) — highlights
- `--b1` (base-100) — chart background
- `--bc` (base-content) — text, labels, grid lines
- `--n` (neutral) — borders, tooltips

---

## File Structure

```
lib/dai/
  analytics/
    user.ex
    plan.ex
    subscription.ex
    invoice.ex
    event.ex
    feature.ex
  ai/
    client.ex
    plan_validator.ex
    sql_executor.ex
    result_assembler.ex
    result.ex
    query_pipeline.ex
    system_prompt.ex
  schema_context.ex

lib/dai_web/
  live/
    dashboard_live.ex
    dashboard_live.html.heex
  components/
    dashboard_components.ex

lib/mix/tasks/
  gen_schema_context.ex

assets/js/
  hooks/
    chart_hook.js

priv/
  ai/
    schema_context.json
  repo/
    seeds.exs
    migrations/
      *_create_plans.exs
      *_create_users.exs
      *_create_subscriptions.exs
      *_create_invoices.exs
      *_create_events.exs
      *_create_features.exs

config/
  runtime.exs  (add ANTHROPIC_API_KEY)
```

---

## Error Handling

All errors surface as inline cards in the dashboard grid:

| Error Source | Error Type | Card Message |
|---|---|---|
| Claude API | Network/timeout | "Could not reach the AI service. Please try again." |
| Claude API | Malformed JSON | "The AI returned an unexpected response. Please try again." |
| Plan validation | Forbidden SQL | "The generated query contained forbidden operations and was blocked." |
| Plan validation | Invalid component | "The AI suggested an unknown visualization type." |
| SQL execution | Query error | "The database query failed: {postgres error message}" |

All error cards include the original prompt and a retry button.

---

## Environment Configuration

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | — | Claude API authentication |
| `AI_MODEL` | No | `claude-sonnet-4-6` | Claude model ID |
| `DATABASE_URL` | No | dev config | Postgres connection |
| `PORT` | No | 4000 | HTTP port |
