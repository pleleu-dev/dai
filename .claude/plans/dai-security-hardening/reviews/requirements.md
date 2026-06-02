# Requirements Coverage (from Plan dai-security-hardening)

## Finding → Task Coverage Map

| # | Requirement / Task | Status | Evidence |
|---|-------------------|--------|----------|
| F#1 | query_scope advisory-only → Phase 2 (enforce) | MET | `lib/dai/ai/plan_validator.ex:71-88` `enforce_scope/2`; `lib/dai/ai/sql_executor.ex:67-69` GUC set via `set_config($1)` |
| F#2 | Bypassable blocklist / unbounded SQL / no timeout | MET | blocklist `plan_validator.ex:21`; LIMIT clamping `plan_validator.ex:97-114`; read-only txn + timeout `sql_executor.ex:31-45` |
| F#3 | Raw Postgres errors leaked | MET | `lib/dai/ai/result.ex:79-80` generic message; `sql_executor.ex:54` Logger.warning logs real detail |
| F#4 | Unauthenticated route + token | MET | `lib/dai/router.ex:26-53` Security section `@moduledoc`; `dashboard_live.ex:1-21` trust model `@moduledoc`; `resolve_user_token/2` at `dashboard_live.ex:274` |
| F#5 | Folders IDOR (no user_token) | MET | migration `priv/repo/migrations/20260602194702_add_user_token_to_folders.exs`; `lib/dai/folders.ex:24-126` all public fns scoped; `fetch_owned/3` at `folders.ex:120-125` |
| F#6 | No rate limit / prompt cap | MET | `lib/dai/rate_limiter.ex` token bucket; `dashboard_live.ex:586-599` `run_query/2` checks length + `RateLimiter.take/2` |
| F#14 | Result.t() type duplication (low) | MET | `lib/dai/ai/component.ex:5` `@type component_type`; `lib/dai/ai/result.ex:7` references `Dai.AI.Component.component_type()` |

## Phase 0 — Config foundations

| # | Task | Status | Evidence |
|---|------|--------|----------|
| T0.1 | Config readers: `readonly_repo/0`, `sql_repo/0`, `statement_timeout_ms/0`, `max_rows/0`, `max_prompt_length/0`, `rate_limit/0` with safe defaults | MET | `lib/dai/config.ex:79-120` all six readers present with module-attr defaults |
| T0.2 | Unit-test new readers; `async: false` | MET | `test/dai/config_test.exs:1` `async: false`; defaults + override tests for all six at lines 39–103 |

## Phase 1 — Read-only SQL execution boundary

| # | Task | Status | Evidence |
|---|------|--------|----------|
| T1.1 | `ensure_limit/1` clamps via `@limit_clause` regex to `min(Component.default_limit, Config.max_rows)` | MET | `plan_validator.ex:97-122` |
| T1.2 | `SqlExecutor.execute/1` wraps in `sql_repo().transaction` with `SET LOCAL transaction_read_only = on` + `SET LOCAL statement_timeout`; D7 documented | MET | `sql_executor.ex:31-45`; D7 rationale in `@moduledoc` lines 14-20 |
| T1.3 | `@forbidden_pattern` extended (`copy|vacuum|merge`); `@moduledoc` explains blocklist is defense-in-depth | MET | `plan_validator.ex:21` pattern; `@moduledoc` lines 3-15 |
| T1.4 | Tests: clamping + injection + write-blocked + connection-still-usable | MET | `test/dai/ai/plan_validator_test.exs:145-213`; `test/dai/ai/sql_executor_test.exs:44-63` |

## Phase 2 — Tenant scope enforcement

| # | Task | Status | Evidence |
|---|------|--------|----------|
| T2.1 | `scope` threaded through pipeline; `enforce_scope/2` → `:scope_violation` on missing column; structured Logger.warning | MET | `query_pipeline.ex:10-33`; `plan_validator.ex:69-91`; `sql_executor.ex:24` |
| T2.2 | GUC via `set_config('dai.scope_value', $1, true)`; D8 documented | MET | `sql_executor.ex:67-69`; D8 rationale in `@moduledoc` lines 63-65 |
| T2.3 | `:scope_violation` → safe user message | MET | `result.ex:73-75` |
| T2.4 | Tests: scope missing→violation+log; present→pass; none→unaffected; action→violation; pipeline run_from_plan/3 | MET | `test/dai/ai/plan_validator_test.exs:215-260`; `test/dai/ai/query_pipeline_test.exs:47-79` |

## Phase 3 — Folders tenant scoping

| # | Task | Status | Evidence |
|---|------|--------|----------|
| T3.1 | Migration: nullable add → backfill 'legacy' → `modify null: false`; indexes on `[:user_token]` both tables + `[:position]` on folders | MET | `priv/repo/migrations/20260602194702_add_user_token_to_folders.exs:9-37` |
| T3.2 | Schemas: `field :user_token`; `cast` + `validate_required` | MET | `lib/dai/folders/folder.ex:10,21-23`; `lib/dai/folders/saved_query.ex:11,22-23` |
| T3.3 | `Dai.Folders` public fns take `user_token` first; ownership writes use `fetch_owned/3`; `@moduledoc` boundary doc | MET | `lib/dai/folders.ex:24-126`; `@moduledoc` lines 1-10 |
| T3.4 | `DashboardLive` all Folders.* call sites pass `user_token` | MET | `dashboard_live.ex:239` local var; grep confirmed `Folders.` calls use `socket.assigns.user_token` or passed `user_token` |
| T3.5 | Tests: two isolation describe blocks (A cannot access B's data → `:not_found`/`NoResultsError`; owner succeeds); dashboard_live_test injects session token | MET | `test/dai/folders_test.exs:58-192`; `test/dai_web/live/dashboard_live_test.exs:77-85` |

## Phase 4 — Auth hardening & error leakage

| # | Task | Status | Evidence |
|---|------|--------|----------|
| T4.1 | `resolve_user_token/2` extracted; `@moduledoc` trust model | MET | `dashboard_live.ex:274-278`; `@moduledoc` lines 1-21 |
| T4.2 | `Dai.Router` `@moduledoc` Security section; standalone router DEMO-ONLY comment | MET | `lib/dai/router.ex:26-53`; README.md referenced in plan (not read but plan notes it) |
| T4.3 | `error_message({:query_failed, _detail})` → generic message; detail logged at `SqlExecutor` | MET | `result.ex:79-80`; `sql_executor.ex:54` |
| T4.4 | `result_test.exs` asserts raw detail absent; scope_violation safe message | MET | `test/dai/ai/result_test.exs:31-48` |

## Phase 5 — Rate limiting & input caps

| # | Task | Status | Evidence |
|---|------|--------|----------|
| T5.1 | `run_query/2` rejects prompts > `Config.max_prompt_length()` with inline `#query-error` assign | MET | `dashboard_live.ex:586-590`; `#query-error` rendered at `dashboard_live.ex:54` |
| T5.2 | Per-socket token bucket in assigns; `init_rate_bucket/0`; `RateLimiter.take/2`; empty → inline error | MET | `lib/dai/rate_limiter.ex`; `dashboard_live.ex:592-598,620-621` |
| T5.3 | Tests: over-long → `#query-error` "too long"; within-max accepted; 2nd rapid (limit:1) → "too quickly" | MET | `test/dai_web/live/dashboard_live_test.exs:205-241` |

## Phase 6 — Test gaps, cleanup, full verification

| # | Task | Status | Evidence |
|---|------|--------|----------|
| T6.1 | `Dai.AI.ClientBehaviour`; `Config.ai_client/0`; `QueryPipeline.run/3` `client:` opt; Mox dep; `client_test.exs`; 3 run/3 end-to-end tests | MET | `lib/dai/ai/client_behaviour.ex`; `config.ex:67-70`; `query_pipeline.ex:8`; `mix.exs:70`; `test/dai/ai/client_test.exs`; `test/dai/ai/query_pipeline_test.exs:81-117` |
| T6.2 | `system_prompt_test.exs`: scope present/absent, `table.column`, embeds schema | MET | `test/dai/ai/system_prompt_test.exs:6-36` |
| T6.3 | Deterministic `render_component(empty_state)` tests via `LazyHTML` | MET | `test/dai_web/live/dashboard_live_test.exs:47-73` |
| T6.4 | LazyHTML `from_document`/`from_fragment` + `query`; `id="explorer-detail"` | MET | `test/dai_web/live/dashboard_live_test.exs:40,178` |
| T6.5 | `Component.component_type/0` `@type`; `Result.t()` references it | MET | `component.ex:5`; `result.ex:7` |
| T6.6 | `{:mox, "~> 1.1", only: :test}` + `{:mix_audit, "~> 2.1"}`; `precommit` runs `deps.audit` | MET | `mix.exs:70-71`; `mix.exs:100` |

## Documented deviations

| Deviation | Status | Evidence |
|-----------|--------|----------|
| D7: `SET LOCAL transaction_read_only = on` instead of `SET TRANSACTION READ ONLY` | MET (implemented as documented) | `sql_executor.ex:35`; `@moduledoc` rationale lines 14-20 |
| D8: `set_config('dai.scope_value', $1, true)` instead of `SET LOCAL ... = $1` | MET (implemented as documented) | `sql_executor.ex:68`; plan note T2.2 |

**Summary**: 30 MET · 0 PARTIAL · 0 UNMET · 0 UNCLEAR
