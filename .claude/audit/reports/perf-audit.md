# Dai Performance Audit

Scope: `lib/dai/` with emphasis on AI pipeline, DashboardLive, Folders, SchemaContext, layout/preferences persistence, and migrations.

**Performance health score: 74 / 100**

Justification: Core architecture is sound — async query execution via `Task.async`, GridStack cards pushed via events (not streams), `:persistent_term` written once at boot, demo schema migrations fully indexed, library persistence tables indexed on `user_token`. The deductions come from one genuinely unbounded resource path (raw AI-driven SQL with no row/time ceiling), an N+1 upsert pattern in layout persistence, a missing index on `dai_folders.position`, and a couple of assign-bloat / connected? issues in the LiveView.

---

## 1. N+1 queries

### 1.1 [MEDIUM] N+1 upsert in batch layout save — `dashboard_layout.ex:64-78`
`save_layouts/2` wraps a transaction, but inside it calls `save_layout/3` per card, and each `save_layout/3` does a `get_by` (SELECT) followed by an INSERT or UPDATE — 2 queries per card. For a dashboard with N cards, every `layout_changed` event (which fires on every drag/resize settle) runs 2N queries.

Fix: replace the read-then-write loop with a single `insert_all` + `:on_conflict` upsert keyed on the existing `unique_index(:user_token, :layout_key)`:

```elixir
def save_layouts(user_token, cards) when is_list(cards) do
  now = DateTime.utc_now() |> DateTime.truncate(:second)
  entries =
    Enum.map(cards, fn c ->
      %{id: Ecto.UUID.generate(), user_token: user_token, layout_key: c["layout_key"],
        x: c["x"], y: c["y"], w: c["w"], h: c["h"], inserted_at: now, updated_at: now}
    end)

  repo().insert_all(__MODULE__, entries,
    on_conflict: {:replace, [:x, :y, :w, :h, :updated_at]},
    conflict_target: [:user_token, :layout_key])
end
```
This collapses 2N queries into 1.

### 1.2 [LOW] Sidebar / dashboard render paths — no N+1 found
`Folders.list_folders/0` and `list_saved_queries/1` each issue exactly one query; the sidebar components (`sidebar_components.ex`) iterate over already-loaded `@folders` / `@folder_queries` lists and access only scalar fields (`folder.id`, `folder.name`, `query.prompt`) — no association access in templates, so no lazy-load N+1. Clean.

### 1.3 [LOW] `load_all_folder_queries` fan-out — `dashboard_live.ex:349-368`
One query to load the folder's saved queries, then one `Task.async` per query firing an independent Claude API call. This is not a DB N+1 (it is intended parallel fan-out) but is unbounded: a folder with 50 saved queries spawns 50 concurrent Anthropic requests from one LiveView process. Consider `Task.async_stream` with `max_concurrency` to cap fan-out and avoid rate-limit/backpressure issues.

---

## 2. Missing database indexes

### 2.1 [LOW] `dai_folders.position` not indexed — `20260331000001_create_dai_folders.exs`
`Folders.list_folders/0` does `order_by(:position)` on every mount and after every folder mutation. `dai_folders` is small in practice, but the column ordered-by on every dashboard load has no index. Add `create index(:dai_folders, [:position])`.

### 2.2 [INFO] `dai_saved_queries` ordered by `position`, filtered by `folder_id`
`list_saved_queries/1` does `where(folder_id: ^id) |> order_by(:position)`. There is an index on `[:folder_id]` (good for the filter). A composite `[:folder_id, :position]` would let Postgres satisfy filter+sort from the index, but given expected row counts this is optional.

### 2.3 Clean: persistence + demo tables
`dai_dashboard_layouts` has `unique_index([:user_token, :layout_key])` + `index([:user_token])`; `dai_dashboard_preferences` has `unique_index([:user_token])`; `dai_saved_queries` indexes `folder_id`; demo tables (subscriptions, invoices, events) index all FKs plus common WHERE/ORDER columns (`status`, `due_date`, `inserted_at`, `name`). All good.

---

## 3. LiveView assign bloat — `dashboard_live.ex`

### 3.1 [MEDIUM] Unconditional DB + cache reads in `mount/1` (runs twice) — `dashboard_live.ex:204-239`
`mount/1` runs once for the static (disconnected) HTTP render and again for the websocket connect. It unconditionally calls `DashboardPreferences.get_preferences/1` (1 query), `DashboardLayout.get_layouts/1` (1 query), `Folders.list_folders/0` (1 query), plus `SchemaContext.get/0` and `SchemaExplorer.get/0` (persistent_term reads). That is ~3 DB queries x 2 renders = 6 queries per page load. The Iron Law here: guard connected-only work, e.g.

```elixir
if connected?(socket) do
  # load layouts/prefs/folders
else
  # assign empty defaults
end
```
The `:persistent_term` reads are cheap and fine to keep; the three DB calls are the ones worth deferring (or moving into `assign_async`).

### 3.2 [LOW] `folder_queries` raw list assign
`@folder_queries` is a plain list assigned and re-assigned on folder open/CRUD. It is bounded to a single folder's queries (small), so streams are not required, but note it is a full-list assign re-pushed on every related event. Acceptable at expected scale.

### 3.3 [LOW] No `temporary_assigns`
`schema_explorer`, `explorer_suggestions`, and `saved_layouts` are held permanently in socket state. `saved_layouts` is only consumed once (encoded into the grid's `data-gs-layout` at initial render) and never read again — it is dead weight in process memory for the session's lifetime. Could be moved to `temporary_assigns: [saved_layouts: %{}]`. Minor.

GridStack cards correctly use `push_event` + `phx-update="ignore"` (by design) — not flagged.

---

## 4. SqlExecutor / PlanValidator — raw user-driven SQL

### 4.1 [HIGH] No row-count bound and no statement timeout on AI-generated SQL — `sql_executor.ex:4-22`, `plan_validator.ex:60-69`
This is the biggest performance (and availability) risk. The SQL string is produced by Claude from untrusted natural-language input and executed via `Ecto.Adapters.SQL.query/3` with **no** `:timeout` and **no** outer row cap. Problems:

1. **LIMIT is only injected when absent.** `ensure_limit/1` (`plan_validator.ex:60`) appends a `LIMIT` *only if the SQL has no `LIMIT` keyword*. If the model emits `LIMIT 5000000` (or `LIMIT 50` on an inner subquery while the outer query returns millions), the validator accepts it unchanged. There is no maximum-LIMIT ceiling.
2. **No statement timeout.** A heavy aggregation / accidental cross join can run for the full default DB timeout (15s) and pin a connection-pool slot, then `SqlExecutor.execute/1` still has to materialize and `Enum.map`-normalize every returned row into a map (`sql_executor.ex:8-12`) on the Task process.
3. **No materialized row cap.** Even with a LIMIT, `data_table` allows `LIMIT 500` and the normalization builds 500 maps; fine — but there is nothing stopping a model-supplied larger LIMIT.

Fixes:
- Add a hard ceiling in `ensure_limit/1`: parse the trailing `LIMIT n` and clamp `n` to `Component.default_limit(component)` (rewrite rather than only-append).
- Pass `timeout:` to the query, e.g. `Ecto.Adapters.SQL.query(repo, sql, [], timeout: 10_000)`, and/or set `SET LOCAL statement_timeout` in a wrapping transaction so a runaway query is killed at the DB.
- Optionally enforce `max_rows` defensively after execution.

### 4.2 [INFO] Forbidden-keyword regex is a blocklist
`@forbidden_pattern` (`plan_validator.ex:8`) blocks write keywords — adequate for the perf scope (prevents expensive writes), but note blocklists are inherently leaky for security. Out of perf scope; flagged for awareness.

---

## 5. Anthropic API client — `client.ex`

### 5.1 [LOW] No retries / no connect timeout — `client.ex:37-50`
`Req.post/2` sets `receive_timeout: 30_000` but no `connect_options` timeout and no `retry:` policy. A transient 429/5xx from Anthropic fails the whole pipeline immediately (`_ -> {:error, :api_error}` swallows the status). Req supports `retry: :transient` with backoff — adding it would smooth over rate limits, especially given the `load_all_folder_queries` fan-out (§1.3) which can trigger 429s. The blanket `_ ->` also discards the status/body, making slow-call diagnosis harder (no logging).

### 5.2 [GOOD] API call does not block the LiveView process
`QueryPipeline.run/3` (which calls the client) is always invoked inside `Task.async` from `run_query/2` and `load_all_folder_queries/2`. The 30s receive_timeout therefore runs off the LiveView process; the UI stays responsive (`loading: true`). Correct design.

### 5.3 [INFO] Boot-time suggestion generation calls the API
`SchemaExplorer.start_link/1` -> `build_explorer_data` -> `generate_boot_suggestions` makes a synchronous Claude API call **during application boot** (`schema_explorer.ex:18`, `:134`). This blocks the supervision tree start for up to 30s on app startup and will crash-loop boot if the API key is missing/Anthropic is down. The child returns `:ignore` so it isn't supervised long-term, but the boot-time blocking call is a startup-latency footgun. Consider deferring suggestion generation to a lazy/async first-use path.

---

## 6. `:persistent_term` usage — `schema_context.ex`, `schema_explorer.ex`

### 6.1 [GOOD] Written once at boot, not in a hot path
`SchemaContext.start_link/1` (`schema_context.ex:13`) and `SchemaExplorer.start_link/1` (`schema_explorer.ex:18`) each call `:persistent_term.put/2` exactly once at boot, returning `:ignore`. `reload/0` exists for explicit manual reload only and is not called on any request path. This avoids the known `:persistent_term` footgun (repeated writes trigger a global heap scan / GC of all processes). Reads use `:persistent_term.get/1-2`. Correct.

### 6.2 [INFO] Boot row-count queries — `schema_explorer.ex:62-130`
`build_explorer_data` runs one `SELECT count(*)` per discovered table at boot (`query_row_count/1`, `:123`) via `Task.async_stream` (good, parallel, 10s timeout). On large tables an unqualified `count(*)` can be slow, and it runs synchronously in `start_link`, adding to boot latency alongside §5.3. Low impact for the demo dataset; worth noting for host apps with large tables. Consider `reltuples` estimate from `pg_class` instead of exact `count(*)`.

---

## Summary of actionable fixes (by priority)

| # | Sev | Location | Fix |
|---|-----|----------|-----|
| 4.1 | HIGH | `sql_executor.ex` / `plan_validator.ex:60` | Clamp LIMIT to a max + add query `timeout:` / `statement_timeout` |
| 1.1 | MED | `dashboard_layout.ex:64` | Replace per-card get+upsert loop with single `insert_all` + `on_conflict` |
| 3.1 | MED | `dashboard_live.ex:204` | Guard the 3 DB loads in `mount` behind `connected?/1` or `assign_async` |
| 5.3 | MED | `schema_explorer.ex:18` | Defer boot-time Claude suggestion call off the supervision start path |
| 2.1 | LOW | `20260331000001_*` | Add `index(:dai_folders, [:position])` |
| 1.3 | LOW | `dashboard_live.ex:349` | Cap fan-out with `Task.async_stream(max_concurrency:)` |
| 5.1 | LOW | `client.ex:37` | Add `retry: :transient` + log non-200 status |
| 3.3 | LOW | `dashboard_live.ex` | `temporary_assigns` for `saved_layouts` (write-once) |
| 6.2 | INFO | `schema_explorer.ex:123` | Use `pg_class.reltuples` estimate instead of exact count for large tables |
