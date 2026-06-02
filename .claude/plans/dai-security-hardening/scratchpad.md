# Scratchpad — Dai Security Hardening

Working notes, decisions, and dead-ends. Source: `.claude/audit/summaries/project-health-2026-06-02.md`.

## Key ground-truth findings (from reading the code, 2026-06-02)

- **Scoping is already plumbed, just not enforced.** `Dai.Router.dai_dashboard/2` already accepts a `scope_value` getter and passes it as `dai_scope_value` in the session. `DashboardLive.build_scope/1` (dashboard_live.ex:577) merges it with `Config.query_scope()` into a `%{column, table, value, ...}` map and threads it to `QueryPipeline.run(prompt, ctx, scope: scope)`. The scope only reaches `SystemPrompt.scope_section/1` (advisory). **Nothing enforces it at execution.** → Enforce at the `SqlExecutor` transaction boundary.
- **`PlanValidator.ensure_limit/1` (plan_validator.ex:60) only appends** a LIMIT when none present. A model-supplied `LIMIT 5000000` passes untouched. Must *clamp* to `Component.default_limit(component)`.
- **`SqlExecutor.execute/1` (sql_executor.ex:4)** runs `Ecto.Adapters.SQL.query(Config.repo(), sql)` — no transaction, no `READ ONLY`, no `statement_timeout`, no row cap, uses the host's read-write repo/role.
- **`Result.error_message({:query_failed, detail})` (result.ex:76)** interpolates the raw Postgres `message` into client-facing text. Leak confirmed.
- **`Dai.Folders` has no `user_token`** on `Folder` or `SavedQuery`. `list_folders/0` is global; `rename_folder/2`, `delete_folder_by_id/1`, `delete_saved_query_by_id/1`, `rename_saved_query/2` do bare `repo().get(...)` with no ownership check → IDOR. `DashboardLayout` (dashboard_layout.ex) is the pattern to mirror: every query `where(user_token: ^token)`, changeset `validate_required([:user_token, ...])`, `unique_constraint([:user_token, ...])`.
- **`Result.t()` type union (result.ex:7-15)** hardcodes the 5 component atoms, duplicating `Dai.AI.Component`. (Audit #14 — deferred to long-term unless cheap.)
- **`@forbidden_pattern` (plan_validator.ex:8)** is a single deny-regex. Read-only DB role is the real fix; keep the regex as defense-in-depth.

## Library constraint (host owns the DB)

Dai is a git dependency; the host owns the Repo, DB connection, schema, and migrations. Therefore:
- We cannot create a read-only Postgres role for them. We **document** it and **support** an optional `:readonly_repo` config that, when set, `SqlExecutor` uses for AI SQL. When unset, we degrade to a `READ ONLY` transaction + `statement_timeout` on the primary repo (weaker but still blocks writes).
- RLS policies are the host's responsibility (their schema). Dai's contribution: set the scope as a transaction-local GUC (`SET LOCAL dai.scope_value = $1`) so host RLS policies can reference `current_setting('dai.scope_value', true)`. Document the recommended policy. Programmatic WHERE-presence check stays as defense-in-depth.

## Decisions

- **D1:** Enforce scope via (a) transaction-local GUC for host RLS + (b) a hard validation that fails the query when scope is configured but the column/value GUC path isn't satisfiable. Reject (don't just warn) when scope configured and SQL lacks the scope column AND no readonly_repo/RLS in play. `warn_if_missing_scope` becomes `enforce_scope` returning `{:error, :scope_violation}`.
- **D2:** Read-only execution always wraps AI SQL in `Repo.transaction(fn -> Repo.query!("SET TRANSACTION READ ONLY"); ... end, timeout:)` with `SET LOCAL statement_timeout`. Prefer `Config.readonly_repo()` when configured.
- **D3:** Sanitize DB errors: `{:query_failed, _}` → generic client message; log the real detail with `Logger.warning`.
- **D4:** Folders gets `user_token` (string, not null). Every public fn takes `user_token` as first arg; LiveView passes `socket.assigns.user_token`. Migration backfills existing rows to a sentinel or is acceptable-to-drop in dev (demo data).
- **D5:** Auth — library can't force auth, but: prefer the host-provided signed session token over `connect_params`; only fall back to a random token when no host token configured (single-tenant/anon mode). Document `on_mount` auth + `user_token`/`scope_value` getters as the supported secure integration. Standalone scaffold route stays open but gets a documented warning (it's the demo).
- **D6:** Rate limit + prompt cap at the `handle_event("query", ...)` boundary in DashboardLive (per-socket token bucket in assigns + `Config.max_prompt_length()` cap). Simple, no new dep.

## Decisions (during /phx:work execution)

- **D7 (deviation from plan T1.2):** Use `SET LOCAL transaction_read_only = on` instead of the plan's literal `SET TRANSACTION READ ONLY`. The latter must be the *first* statement in a transaction; the Ecto SQL sandbox already runs queries in its wrapping transaction, so `SET TRANSACTION READ ONLY` raises "must be called before any query" in tests. `SET LOCAL transaction_read_only = on` is the equivalent GUC with no positional restriction and works in both production (top-level txn) and tests (savepoint). Writes still rejected by the engine. statement_timeout is interpolated as an integer from config (not user input → safe); `SET` cannot take bind params.
- **D8 (Phase 2 GUC):** For the scope GUC, `SET LOCAL dai.scope_value = $1` cannot use a bind param either. Use `SELECT set_config('dai.scope_value', $1, true)` — the parameterized equivalent (is_local=true) — to avoid SQL injection via the scope value.

## Dead-ends / rejected

- ❌ SQL AST parsing to whitelist statements — too heavy, no maintained pure-Elixir Postgres parser; read-only role + RLS is the robust boundary.
- ❌ Forcing a `:readonly_repo` as required — breaks single-tenant host apps that don't need it; keep optional with a safe degraded path.
