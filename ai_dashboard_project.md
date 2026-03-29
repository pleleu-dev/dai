# Phoenix AI Dashboard — Project Overview

> A natural language data interface built on Phoenix LiveView, Ecto, and Claude. Users describe what they want to see in plain English; the system generates the SQL, picks the best visual component, and renders it instantly — no dashboards to configure, no filters to learn.

---

## Table of contents

1. [Vision & problem statement](#1-vision--problem-statement)
2. [Architecture overview](#2-architecture-overview)
3. [Core pipeline](#3-core-pipeline)
4. [Schema discovery & context generation](#4-schema-discovery--context-generation)
5. [AI query engine](#5-ai-query-engine)
6. [Safe SQL execution](#6-safe-sql-execution)
7. [Component rendering system](#7-component-rendering-system)
8. [Theme personalisation](#8-theme-personalisation)
9. [Quick actions](#9-quick-actions)
10. [Missing features — security & multi-tenancy](#10-missing-features--security--multi-tenancy)
11. [Missing features — conversation & UX](#11-missing-features--conversation--ux)
12. [Missing features — data rendering & export](#12-missing-features--data-rendering--export)
13. [Missing features — schema & AI context quality](#13-missing-features--schema--ai-context-quality)
14. [Missing features — dashboards & sharing](#14-missing-features--dashboards--sharing)
15. [Missing features — reliability & cost](#15-missing-features--reliability--cost)
16. [Technology stack](#16-technology-stack)
17. [Implementation status](#17-implementation-status)
18. [Prioritised roadmap](#18-prioritised-roadmap)

---

## 1. Vision & problem statement

Traditional business dashboards require a product or engineering investment to build: someone must decide which metrics matter, design the filters, write the queries, and maintain the charts as the schema evolves. This creates a bottleneck — non-technical users are always dependent on developers to answer data questions.

**The AI Dashboard flips this model.** Instead of building dashboards upfront, the system presents a single chat prompt. Users describe what they want in plain English — "show me new signups this month", "compare revenue by country for the last 6 months", "list orders that haven't shipped" — and the system:

- Interprets the intent
- Generates safe, correct SQL against the live schema
- Chooses the best visual representation (chart, table, KPI metric)
- Renders the result instantly via LiveView with no page reload

The result is a self-service data layer that scales with the team's questions, not with engineering capacity.

---

## 2. Architecture overview

The system is structured in four logical layers that communicate synchronously within a single LiveView process, with async task offload for the Claude API call.

```
┌─────────────────────────────────────────────────────────┐
│  Browser (Phoenix LiveView over WebSocket)              │
│  Chat prompt → result rendered in real time             │
└────────────────────┬────────────────────────────────────┘
                     │ phx-submit / handle_event
┌────────────────────▼────────────────────────────────────┐
│  AI Orchestrator — QueryPipeline                        │
│  Coordinates: schema context → Claude → SQL → component │
└──────┬─────────────────────┬───────────────────────────-┘
       │                     │
┌──────▼──────┐     ┌────────▼────────────────────────────┐
│ Claude API  │     │  Safe SQL Executor (Ecto/Postgres)  │
│ NL → SQL    │     │  Validation + row limit enforcement  │
│ + component │     └────────────────────────────────────-┘
│ selection   │
└─────────────┘
┌─────────────────────────────────────────────────────────┐
│  Component Renderer                                     │
│  bar_chart / line_chart / pie_chart / data_table / kpi  │
│  All themed via DaisyUI CSS variables                   │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  Schema Context Layer                                   │
│  Mix task → introspects Ecto schemas → JSON snapshot    │
│  GenServer caches the result, reloads on demand         │
└─────────────────────────────────────────────────────────┘
```

All state lives on the server. The browser only receives HTML diffs over the WebSocket — there is no client-side state management framework.

---

## 3. Core pipeline

Every user query goes through exactly five sequential steps:

**Step 1 — Schema context injection**
Before calling Claude, the system retrieves a pre-generated, structured description of the database schema from an in-memory cache (GenServer backed by a JSON file). This context includes table names, column names and types, primary keys, associations, and any human-readable annotations. Only relevant tables are injected for large schemas (see vector-based table selection, section 13).

**Step 2 — NL → plan via Claude**
The user's prompt and the schema context are sent to Claude with a strict system prompt. Claude responds with a structured JSON plan containing: a SQL query, a component type, a human-readable title, a description, and axis configuration for charts. If the prompt is ambiguous, Claude returns a clarification question instead of a SQL query.

**Step 3 — Plan validation**
Before any SQL is executed, the plan is validated: forbidden keywords (INSERT, UPDATE, DELETE, DROP, etc.) are blocked, a LIMIT clause is enforced, and the component type is cross-checked against the shape of the result (e.g. a KPI metric needs exactly one scalar value).

**Step 4 — Query execution**
The validated SQL runs against the database via Ecto's raw query interface. Results are returned as a list of maps keyed by column name.

**Step 5 — Component assembly & render**
The pipeline assembles a component struct from the plan and the query result, assigns it to the LiveView socket, and Phoenix diffs the DOM — the browser updates without a reload.

---

## 4. Schema discovery & context generation

### The Mix task

A custom Mix task (`mix gen_schema_context`) discovers all Ecto schema modules in the application by inspecting the compiled module list and filtering for modules that export the `__schema__/1` function. For each schema it extracts:

- Source table name
- All non-virtual fields with their Ecto types
- Primary key fields
- Associations (has_many, belongs_to, many_to_many) with cardinality and related module
- Embedded schemas

The output is written to `priv/ai/schema_context.json` — a structured, human and machine-readable snapshot of the entire data model.

### Automation

The task is wired into Mix aliases so it runs automatically:

- On every `mix ecto.migrate` — schema stays in sync after every migration
- On every `mix phx.server` — dev server always starts with a fresh snapshot
- In CI/CD before the release is built — snapshot is baked into the release artifact

### Runtime caching

A GenServer loads the JSON file at application startup and holds the formatted schema string in memory. Individual LiveView processes call into the GenServer to retrieve it — no file I/O per request. In development, the cache can be reloaded without restarting the server.

---

## 5. AI query engine

### System prompt design

The system prompt passed to Claude contains three sections:

1. **Role and output contract** — Claude must respond only with a valid JSON object in a defined shape. No markdown, no explanation, no wrapping.
2. **Schema context** — the formatted table/column/association description for the relevant tables.
3. **Decision rules** — how to choose between component types based on result shape; the LIMIT requirement; the read-only constraint; when to return a clarification question instead of SQL.

### Component selection logic

Claude selects the component type based on the nature of the data being returned:

| Data shape | Component chosen |
|---|---|
| Single scalar value | `kpi_metric` |
| Time series (date + value pairs) | `line_chart` |
| Category comparisons | `bar_chart` |
| Part-of-whole proportions | `pie_chart` |
| Multiple columns / raw rows | `data_table` |

### Clarification flow

If the prompt is genuinely ambiguous — "recent users" with no timeframe, "compare sales" with no dimension specified — Claude returns a `needs_clarification` field with a follow-up question. The orchestrator detects this and routes the question back to the chat as an assistant message rather than executing any SQL.

---

## 6. Safe SQL execution

### Validation layer

Every SQL string produced by Claude passes through a validation layer before hitting the database:

- **Keyword blocklist** — the query is lowercased and scanned for INSERT, UPDATE, DELETE, DROP, TRUNCATE, ALTER, CREATE, GRANT, REVOKE, EXEC, EXECUTE. Any match causes an immediate rejection.
- **LIMIT enforcement** — if no LIMIT clause is present, one is appended automatically (default: 500 rows for tables, 50 for charts).
- **Parameterisation** — all user-provided values (where applicable) are passed as Ecto query parameters, never interpolated into the SQL string.

### Execution

Validated queries run via `Ecto.Adapters.SQL.query/3` — Ecto's raw SQL interface that bypasses the query DSL while still using the connection pool, telemetry, and sandbox in tests. Results are returned as `%Postgrex.Result{}` structs with column names and row tuples, which are then normalised into a list of maps.

---

## 7. Component rendering system

### Server-side components

All visual components are Phoenix function components rendered on the server. The LiveView assigns a component struct after each successful query, and the template pattern-matches on the `type` field to render the appropriate component. This means no JSON is sent to the browser — only HTML diffs.

### Component types

**KPI metric** — a single large number with a label. Used for scalar results like counts, sums, or averages. Supports optional trend indicator (up/down from previous period) when the query returns a comparison value.

**Bar chart** — categorical comparisons. Rendered via Chart.js through a LiveView hook. Supports vertical and horizontal orientation. Axis labels, grid lines, and tooltip colours all inherit from the active DaisyUI theme.

**Line chart** — time series data. Supports smooth curves, filled area under the line, and multi-series (multiple datasets on the same axes). Point markers optional based on data density.

**Pie / donut chart** — proportional data. Automatically switches to donut style for more than 4 segments. Colours are drawn from the active theme's semantic palette.

**Data table** — raw row data with sortable column headers, zebra striping, and horizontal scroll for wide result sets. Supports up to 500 rows with virtual scrolling planned for larger sets.

### Chart.js hook

Charts are rendered via a LiveView JavaScript hook that mounts a Chart.js instance on the canvas element. The hook reads DaisyUI CSS variables at render time to source all colours — background, borders, text, tooltips. A `MutationObserver` watches the `data-theme` attribute on the `<html>` element and automatically re-renders any mounted chart when the user switches theme, with no page reload.

---

## 8. Theme personalisation

### DaisyUI integration

Phoenix 1.8 ships with DaisyUI 5 and Tailwind v4 out of the box. DaisyUI's theming system works by setting a `data-theme` attribute on the root `<html>` element — all component colours, backgrounds, and borders resolve from CSS variables that change with the theme. This means the entire application UI, including charts, re-themes with a single attribute change.

### Available themes

The system exposes a curated set of DaisyUI themes via a dropdown in the top navigation bar: Light, Dark, Cupcake, Business, Corporate, Synthwave, Cyberpunk, and Retro. The full DaisyUI theme library (30+ themes) can be surfaced with no additional code.

### Persistence

The selected theme is stored in the server-side session and applied at the root layout level — the `data-theme` attribute is rendered server-side so there is no flash of the wrong theme on page load. The theme selection is also synced to `localStorage` via a small JS snippet so it survives session expiry.

### Chart theme sync

Because Chart.js is a canvas-based library, it does not automatically inherit CSS variables. The hook reads the computed DaisyUI variables at mount time and passes them as explicit colour values to Chart.js. The `MutationObserver` pattern ensures that switching themes updates all visible charts without requiring a page reload or any server round-trip.

---

## 9. Quick actions

### Purpose

Users should not have to retype the same queries repeatedly. Quick actions are pre-configured prompts surfaced as clickable chips above the chat input. Clicking one fires the full query pipeline exactly as if the user had typed the prompt manually.

### Two tiers of actions

**System defaults** — a set of 5–8 common queries that appear for all users before they have configured their own. These are defined in application code and cover the most common cross-domain questions (new users, revenue trends, unshipped orders, etc.).

**Pinned user actions** — after any successful query, a "Save" button appears on the result card. Clicking it writes the prompt to the `ai_quick_actions` database table, associated with the current user. Pinned actions appear above the system defaults and persist across sessions.

### Data model

Each quick action record stores: a short display label (max 60 characters), the full prompt text, an icon type (chart, table, kpi, or custom), a position integer for ordering, and a pinned boolean. Actions are scoped to a user via a foreign key with cascade delete.

### Management

Users can remove a pinned action by hovering the chip and clicking the × button. The position field supports drag-to-reorder via a Sortable.js LiveView hook — dragging chips fires a `reorder` event that updates all position values in a single database transaction.

---

## 10. Missing features — security & multi-tenancy

> These are blocking issues for any production deployment with real user data.

### Row-level scoping

**Problem:** The current implementation generates SQL without any awareness of the logged-in user's organisation or permission boundary. A query like `SELECT * FROM users` returns all users in the database regardless of who is asking.

**Solution:** The query execution layer must inject a mandatory WHERE clause before every query runs. The orchestrator receives the current user's `org_id` (or equivalent tenant identifier) and appends `AND org_id = $1` to every generated query. Claude is also instructed in the system prompt to always scope to the current organisation, but the enforcement must happen at the execution layer — never trust the AI to be the sole security control.

### Schema visibility control

**Problem:** The full schema context is currently injected into every Claude prompt, including tables that contain sensitive data (PII, payment details, internal audit logs) that specific users should never be able to query.

**Solution:** A per-role schema allowlist. Tables are tagged in the schema annotation system (see section 13) with visibility levels. When building the Claude prompt, only tables accessible to the current user's role are included. A finance analyst sees revenue tables; a support agent sees ticket and user tables; neither sees internal audit or system tables.

### Role-based table access

An extension of schema visibility — roles define not just which tables are visible but which operations are permitted. A read-only analyst role can SELECT but cannot query tables tagged as write-audit or admin. Role definitions are stored in application config or a database table and applied at both the schema context level and the SQL validation level.

### Query audit log

Every query that runs against the database — including the generated SQL, the user who triggered it, the timestamp, the row count returned, and the Claude token usage — should be written to an append-only `ai_query_logs` table. This serves compliance requirements, enables debugging of bad SQL, and provides the data needed for cost tracking (section 15).

---

## 11. Missing features — conversation & UX

### Multi-turn conversation

**Problem:** Every query is currently stateless. If a user asks "show me revenue last month" and then follows up with "now break that down by country", the second query has no knowledge of the first — Claude will misinterpret "that" and likely produce an unrelated query.

**Solution:** The LiveView maintains a conversation history list — the last N message pairs (user prompt + assistant response including the generated SQL) are passed to Claude on every subsequent call. Claude can then reference prior context, refine previous queries, and apply incremental filters. The history is capped at a configurable window (e.g. last 6 exchanges) to keep token counts manageable.

### Query history sidebar

A collapsible sidebar panel that lists all queries the user has run in the current session and in previous sessions (stored in the `ai_query_logs` table). Each entry shows the prompt, the component type, and the timestamp. Clicking an entry re-runs the query (in case the underlying data has changed) or restores the last result from cache. This replaces the need to scroll up through a long chat to find a previous answer.

### Improved clarification flow

When Claude returns a clarification question, the current implementation shows it as a plain text message. A better UX presents it as a structured follow-up with suggested options where possible — "Do you mean the last 7 days, 30 days, or this calendar month?" rendered as clickable chips rather than requiring the user to type a follow-up. Claude is prompted to return structured clarification options when the ambiguity is bounded.

### Drag-to-reorder quick actions

The data model already includes a `position` integer field on quick action records. The UI needs a Sortable.js LiveView hook that enables drag-and-drop reordering of the quick action chips, firing a `reorder` event that updates all position values in a single database transaction.

---

## 12. Missing features — data rendering & export

### Streaming Claude response

**Problem:** The current implementation shows a spinner while the full Claude response is awaited. For complex queries this can take 3–8 seconds with no feedback.

**Solution:** Use the Anthropic streaming API (`stream: true`) and pipe the token stream through a LiveView `send` loop. The chat displays a "thinking..." message that updates character by character as Claude reasons through the query, giving users the sense of a live response rather than a black box. The final JSON plan is extracted from the completed stream.

### Export to CSV

After a data table or chart is rendered, a download button allows the user to export the raw result set as a CSV file. The export is generated server-side from the in-memory result data — no additional database query is needed. The filename defaults to a slugified version of the query title plus a timestamp.

### Export chart as PNG

A "Download chart" button captures the Chart.js canvas as a PNG using the browser's native `canvas.toDataURL()` API. This is implemented entirely in the JavaScript hook with no server round-trip. The downloaded image uses the current theme's colours so it matches what the user sees on screen.

### Additional component types

**Scatter chart** — for correlation data (two continuous variables). Useful for questions like "plot order value vs customer lifetime value".

**Heatmap** — for two-dimensional frequency data (e.g. activity by hour-of-day and day-of-week). Requires a custom D3 or Chart.js Matrix plugin renderer.

**Funnel chart** — for conversion and drop-off sequences. Useful for product analytics questions about user activation steps.

**Geo map** — for geographic data when a column contains country or region codes. Rendered via a lightweight Leaflet.js hook with a choropleth colour scale.

**Multi-series line chart** — the current line chart supports a single dataset. Multi-series support allows "compare revenue across product lines over the last year" to render as a single chart with one line per product.

### Drill-down on chart click

Clicking a bar or pie segment fires a `phx-click` event that automatically generates a follow-up query drilling into that specific segment. For example, clicking the "France" bar in a revenue-by-country chart auto-prompts "show me the breakdown of revenue in France by product category". This uses the conversation context (section 11) to be aware of the parent query.

---

## 13. Missing features — schema & AI context quality

### Table and column annotations

**Problem:** Ecto column names are often abbreviated or technical (`txn_amt`, `usr_acq_src`, `b2b_flag`). Claude must guess their meaning from context, which leads to incorrect SQL for non-obvious columns.

**Solution:** An annotation system that lets developers add business-readable descriptions to tables and columns without modifying the Ecto schema. Two implementation options:

- **Module attributes** — a `@ai_description` attribute on the schema module that the Mix task picks up during introspection.
- **Sidecar YAML** — a `priv/ai/schema_annotations.yml` file mapping table and column names to descriptions. Easier to edit without touching Elixir code and accessible to non-developers.

The annotations are merged into the schema context JSON during generation and included in the Claude prompt alongside column names and types.

### Vector-based table selection

**Problem:** For applications with 50+ tables, injecting the full schema context into every Claude call is expensive (token cost) and noisy (Claude has more opportunity to select the wrong table).

**Solution:** Embed each table's description using a text embedding model at schema generation time. At query time, embed the user's prompt and compute cosine similarity against all table embeddings. Only the top 5–10 most relevant tables are injected into the Claude prompt. This reduces both token cost and SQL accuracy errors for large schemas.

### Query result caching

Identical prompts from the same user within a configurable window (e.g. 5 minutes) should return the cached result rather than re-running the Claude call and database query. The cache key is a hash of the prompt and the user's org context. ETS is sufficient for single-node deployments; Redis (via Redix) is needed for multi-node.

### Few-shot examples in prompt

The system prompt currently relies on Claude's general SQL knowledge. Including 3–5 domain-specific example prompt/SQL pairs in the system prompt (tailored to the application's actual schema and business terminology) significantly improves first-attempt SQL accuracy. Examples are defined in application config and updated as new patterns emerge from the query audit log.

---

## 14. Missing features — dashboards & sharing

### Save results as a dashboard

After running several queries in a session, a user can select a subset of the results and arrange them into a named dashboard — a grid layout of multiple components that persists beyond the session. Dashboards are stored in a `ai_dashboards` table with a JSON layout definition (component type, position, size, and the prompt that generated each tile). The dashboard view is a separate LiveView that re-runs all constituent queries on load.

### Auto-refresh on schedule

Pinned dashboards and quick actions can be configured to run automatically on a schedule (hourly, daily, weekly). Oban is used as the job queue — a scheduled Oban worker re-runs the stored prompts, writes the results to a cache table, and optionally sends a notification. Users configure the schedule per dashboard from the dashboard settings panel.

### Shareable result links

Any rendered result can be shared via a URL. Two modes: a public snapshot (the result data is frozen at time of sharing, accessible without login) and a live link (re-runs the query on load, requires the recipient to be authenticated). Snapshot links use a short token stored in a `ai_shared_results` table with an optional expiry date.

### Slack and email digest

A delivery layer that sends scheduled dashboard results to Slack channels or email recipients. Oban workers handle the scheduling. Slack delivery uses the Slack API to post a message with a rendered PNG of each chart (exported server-side via a headless browser or a server-side chart rendering library). Email delivery uses Swoosh with an HTML template that embeds the chart images inline.

---

## 15. Missing features — reliability & cost

### Rate limiting per user

Without rate limiting, a single user can trigger unlimited Claude API calls, which has both cost and abuse implications. Hammer (or ex_rated) is used to enforce a per-user call limit (e.g. 30 queries per hour). When the limit is hit, the UI shows a friendly message with the time until the limit resets. Admins are exempt from the limit or have a higher cap configured per role.

### Cost tracking per query

Every Claude API response includes token usage in the response metadata (input tokens, output tokens). This is written to the query audit log alongside the query record. A cost estimation module converts token counts to USD based on the current model's pricing. Aggregated cost reports are surfaced in an admin panel — cost per user, cost per day, most expensive query patterns. This data is essential for capacity planning and identifying prompts that should be cached or replaced with pre-written SQL.

### Query timeout and cancellation

Long-running SQL queries can block database connections and degrade the application for other users. Two mitigations: a configurable `statement_timeout` set on the Postgres connection before each AI-generated query runs (e.g. 10 seconds), and a cancel button in the LiveView UI that terminates the async Task and sends a Postgres query cancellation signal. The UI shows a timeout error message with a suggestion to refine the query.

### Retry logic and graceful degradation

Claude API calls can fail transiently (rate limits, network errors, model overload). The pipeline implements an exponential backoff retry with a maximum of 3 attempts. If all retries fail, the user sees a human-readable error message with a "Try again" button rather than a stack trace. Persistent failures are logged with enough context (prompt, schema context, error) to diagnose the issue.

---

## 16. Technology stack

| Layer | Technology | Role |
|---|---|---|
| Web framework | Phoenix 1.8 | Request handling, routing, LiveView |
| Real-time UI | Phoenix LiveView 1.1 | WebSocket-based server-rendered UI |
| CSS framework | Tailwind v4 + DaisyUI 5 | Utility classes + theme system |
| ORM | Ecto 3.x | Schema introspection, query execution |
| Database | PostgreSQL | Primary data store |
| AI model | Claude Sonnet (Anthropic) | NL→SQL, component selection |
| HTTP client | Req | Claude API calls |
| Charts | Chart.js (via LiveView hook) | Client-side chart rendering |
| Job queue | Oban | Scheduled refresh, digest delivery |
| Caching | ETS / GenServer | Schema context, query result cache |
| Rate limiting | Hammer | Per-user API call limits |
| Email | Swoosh | Digest delivery |

---

## 17. Implementation status

### Built

| Feature | Status |
|---|---|
| Mix task schema generation | ✅ Complete |
| GenServer schema cache | ✅ Complete |
| Claude NL→SQL pipeline | ✅ Complete |
| Safe SQL executor with blocklist | ✅ Complete |
| KPI metric component | ✅ Complete |
| Bar chart component | ✅ Complete |
| Line chart component | ✅ Complete |
| Pie chart component | ✅ Complete |
| Data table component | ✅ Complete |
| Chart.js LiveView hook | ✅ Complete |
| DaisyUI theme picker | ✅ Complete |
| Theme-aware chart re-render | ✅ Complete |
| Theme persistence (session) | ✅ Complete |
| Quick actions — system defaults | ✅ Complete |
| Quick actions — pin from result | ✅ Complete |
| Quick actions — unpin on hover | ✅ Complete |
| Quick actions — DB persistence | ✅ Complete |
| LiveView chat interface | ✅ Complete |
| Clarification question routing | ✅ Complete |

### Not yet built

| Feature | Priority |
|---|---|
| Row-level scoping per org | 🔴 Blocking |
| Schema visibility control | 🔴 Blocking |
| Query audit log | 🔴 Blocking |
| Multi-turn conversation | 🔴 High |
| Table/column annotations | 🔴 High |
| Streaming Claude response | 🟠 High |
| Query history sidebar | 🟠 Medium |
| Role-based table access | 🟠 Medium |
| Rate limiting per user | 🟠 Medium |
| Cost tracking per query | 🟠 Medium |
| Drag-to-reorder quick actions | 🟡 Medium |
| Export to CSV | 🟡 Medium |
| Export chart as PNG | 🟡 Medium |
| Query result caching | 🟡 Medium |
| Vector-based table selection | 🟡 Medium |
| Few-shot examples in prompt | 🟡 Medium |
| Query timeout and cancellation | 🟡 Medium |
| Retry logic / graceful degradation | 🟡 Medium |
| Additional chart types (scatter, heatmap, funnel) | 🟢 Nice to have |
| Geo map component | 🟢 Nice to have |
| Drill-down on chart click | 🟢 Nice to have |
| Save results as dashboard | 🟢 Nice to have |
| Auto-refresh on schedule (Oban) | 🟢 Nice to have |
| Shareable result links | 🟢 Nice to have |
| Slack / email digest | 🟢 Nice to have |
| Improved clarification with option chips | 🟢 Nice to have |

---

## 18. Prioritised roadmap

### Phase 1 — Production-safe (do before any real user sees this)

1. **Row-level scoping** — inject org-scoped WHERE clauses at the execution layer, not just in the prompt.
2. **Schema visibility control** — allowlist tables per role before injecting into the Claude prompt.
3. **Query audit log** — append-only log of every SQL execution with user, timestamp, and token cost.

### Phase 2 — Quality of experience

4. **Multi-turn conversation** — pass last 6 message pairs to Claude on every call.
5. **Table/column annotations** — sidecar YAML or module attributes for business-readable schema descriptions.
6. **Streaming Claude response** — replace the spinner with token-by-token output.
7. **Query history sidebar** — retrieve and re-run past queries.

### Phase 3 — Scale and cost

8. **Rate limiting** — Hammer, per user, configurable per role.
9. **Cost tracking** — token usage in audit log, admin cost report.
10. **Query result caching** — ETS cache keyed on prompt hash + org context.
11. **Query timeout** — Postgres statement_timeout + LiveView cancel button.
12. **Vector-based table selection** — embed schema, inject only relevant tables.

### Phase 4 — Product expansion

13. **Save as dashboard** — grid layout, persist to DB.
14. **Auto-refresh** — Oban scheduled re-runs for saved dashboards.
15. **Export** — CSV download, chart PNG export.
16. **Additional chart types** — scatter, heatmap, funnel, geo map.
17. **Drill-down on click** — auto-generate follow-up query on chart element click.
18. **Sharing** — snapshot URLs, live links, Slack/email digest.

---

*Generated from the Phoenix AI Dashboard project conversation — March 2026.*
