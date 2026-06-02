# Plan: Dai Security Hardening (NL→SQL dashboard)

**Source:** `.claude/audit/summaries/project-health-2026-06-02.md` (Security 28/100 → CRITICAL).
**Goal:** Close the 5 critical/high security findings without breaking the library-as-git-dependency model. Every change configurable by host apps via `Dai.Config`; host owns the Repo/DB.
**Depth:** deep · **Skip /phx:work auto-start** (Iron Law #1).

## Finding → Task coverage map (every audit finding has a task)

| Audit finding | Phase / Task |
|---|---|
| #1 query_scope advisory-only | Phase 2 |
| #2 bypassable blocklist / unbounded SQL / no timeout | Phase 1 |
| #3 raw Postgres errors leaked | Phase 4 (T4.3) |
| #4 unauthenticated route + token | Phase 4 (T4.1–4.2) |
| #5 Folders IDOR (no user_token) | Phase 3 |
| #6 no rate limit / prompt cap | Phase 5 |
| #14 Result.t() type duplication (low) | Phase 6 (T6.5, optional) |
| Untested query_scope / PlanValidator injection | woven into Phases 1–3 + Phase 6 |

---

## Phase 0 — Config foundations `[config]`

- [x] **T0.1** Add `Dai.Config` readers (config.ex), all with safe defaults — added `readonly_repo/0`, `sql_repo/0` (= `readonly_repo() || repo()`), `statement_timeout_ms/0` (15s), `max_rows/0` (1000), `max_prompt_length/0` (2000), `rate_limit/0` (20/60s); defaults as module attrs.
- [x] **T0.2** Unit-test new readers in `test/dai/config_test.exs` — added defaults + override tests; set module `async: false` (global app env mutation).

**Verify:** `mix compile --warnings-as-errors && mix test test/dai/config_test.exs`

---

## Phase 1 — Read-only SQL execution boundary `[ecto]` (audit #2)

- [x] **T1.1** `PlanValidator.ensure_limit/1` — clamps via `@limit_clause` regex to `min(Component.default_limit, Config.max_rows)`; rewrites over-large/`LIMIT ALL`, appends when missing, preserves small.
- [x] **T1.2** `SqlExecutor.execute/1` — wraps SQL in `sql_repo().transaction` with `SET LOCAL transaction_read_only = on` + `SET LOCAL statement_timeout` (D7: read_only GUC not `SET TRANSACTION READ ONLY`, sandbox-compatible); failed query → `repo.rollback({:query_failed, msg})`; kept Postgrex normalization.
- ~~T1.2 orig~~ wrap AI SQL in a **read-only transaction with a statement timeout**, using `Dai.Config.sql_repo()`:
  ```elixir
  repo = Dai.Config.sql_repo()
  repo.transaction(fn ->
    repo.query!("SET TRANSACTION READ ONLY")
    repo.query!("SET LOCAL statement_timeout = #{Dai.Config.statement_timeout_ms()}")
    # (Phase 2 injects SET LOCAL dai.scope_value here)
    case repo.query(sql) do ... end
  end, timeout: Dai.Config.statement_timeout_ms() + 1_000)
  ```
  Keep Postgrex type normalization. Map `%Postgrex.Error{}` to `{:error, {:query_failed, message}}` (sanitized in Phase 4).
- [x] **T1.3** Kept `@forbidden_pattern` (added `copy|vacuum|merge`); documented in `@moduledoc` that the blocklist is defense-in-depth and the read-only execution layer is the real boundary (pg_/CTE/COPY PROGRAM can't be regex-killed).
- [x] **T1.4** Tests added — clamping (over-large/ALL/data_table/preserve/append/max_rows ceiling), injection (stacked, comment-bypass, EXEC/CREATE/COPY); SqlExecutor write-blocked (`UPDATE` → read-only error) + connection-still-usable. pg_read_file documented as DB-boundary-contained, not validator.

**Verify:** `mix test test/dai/ai/plan_validator_test.exs test/dai/ai/sql_executor_test.exs`
**Docs:** README — document `:readonly_repo` setup (host creates a Postgres role `GRANT SELECT`, configures a second Ecto repo).

---

## Phase 2 — Tenant scope enforcement `[ecto]` (audit #1)

Scope already flows to `QueryPipeline.run(scope:)`; make it **enforced**, not advisory.

- [x] **T2.1** Threaded `scope` through `QueryPipeline.run_from_plan/3` → `PlanValidator.validate/2` + `SqlExecutor.execute/2`. `warn_if_missing_scope/1` → `enforce_scope/2`: scope active + SQL lacks column → `{:error, :scope_violation}` (logs SQL via structured `Logger.warning`).
- [x] **T2.2** GUC set via `set_config('dai.scope_value', $1, true)` (D8 — `SET LOCAL ... = $1` can't bind-param; `set_config` is the parameterized equivalent, no injection). RLS policy doc → Phase 4 README.
- [x] **T2.3** `Result` `:scope_violation` → "This query was blocked because it wasn't scoped to your data."; offending SQL logged at `:warning` in `enforce_scope`.
- [x] **T2.4** Tests: plan_validator scope (missing→violation+log, present→pass, none→unaffected, action→violation) + query_pipeline run_from_plan/3 (unscoped blocked pre-DB, scoped executes). CaptureLog asserts on message (custom metadata not in default formatter).

**Verify:** `mix test test/dai/ai/`
**Iron Law check:** uses `with`/`case` for sequential validation; no `String.to_atom` on user input; GUC value parameterized (no SQL injection via scope).

---

## Phase 3 — Folders tenant scoping `[ecto]` `[liveview]` (audit #5, IDOR)

Mirror the existing `DashboardLayout` `user_token` pattern.

- [x] **T3.1** Migration `20260602194702_add_user_token_to_folders.exs` — add nullable `user_token` → backfill `'legacy'` sentinel → `modify null: false` (reversible via `from:`); indexes `[:user_token]` on both + `[:position]` on folders. Verified migrate/rollback/migrate.
- [x] **T3.2** Schemas: `field :user_token, :string` cast + `validate_required([:user_token, ...])` on both changesets.
- [x] **T3.3** `Dai.Folders` — `user_token` first arg on all public fns; reads `where(user_token:)`, ownership writes `get_by(id:, user_token:)` → `nil → {:error, :not_found}`. `@moduledoc` documents the boundary.
- [x] **T3.4** `DashboardLive` — all ~12 `Folders.*` sites pass `user_token` (mount uses local var; handlers + `reload_folders/1`/`reload_folder_queries/1` read `socket.assigns.user_token`). Compiler confirmed completeness. (`SidebarComponents` only uses unchanged `default_folder_name/0`.)
- [x] **T3.5** Tests: rewrote `folders_test.exs` with user_token + two isolation describe blocks (A cannot list/get/rename/delete B's folder/query → `{:error, :not_found}`/`NoResultsError`; owner succeeds). Updated `dashboard_live_test.exs` folder panel to inject session token so fixtures match the view's token.

**Verify:** `mix ecto.migrate && mix test test/dai/folders_test.exs test/live/dashboard_live_test.exs`

---

## Phase 4 — Auth hardening & error leakage `[liveview]` (audit #3, #4)

- [x] **T4.1** `DashboardLive.mount/3` — extracted `resolve_user_token/2` (session token preferred, connect_params fallback, random last); added `@moduledoc` "Identity & trust model".
- [x] **T4.2** `Dai.Router` `@moduledoc` Security section (gate route, signed `user_token`, `scope_value`+RLS, demo-route warning) + standalone `dai_web/router.ex` DEMO-ONLY comment + README "Security" section (auth, readonly_repo role, RLS policy, limits/rate-limit config).
- [x] **T4.3** `Result.error_message({:query_failed, _detail})` → generic "The database query failed. Please rephrase your question."; real detail logged via `Logger.warning` at the `SqlExecutor` boundary (both error branches).
- [x] **T4.4** `result_test.exs` — asserts raw Postgres detail absent from `error/2` output (generic message); + scope_violation safe message.

**Verify:** `mix test test/dai/ai/result_test.exs test/live/dashboard_live_test.exs`

---

## Phase 5 — Rate limiting & input caps `[liveview]` (audit #6)

- [x] **T5.1** `run_query/2` rejects prompts > `Config.max_prompt_length()` with an inline `#query-error` assign (no pipeline call). NOTE: `Dai.Layouts.app` doesn't render flash and host-layout path bypasses it → used inline error assign (passed to `query_input` component) instead of `put_flash`.
- [x] **T5.2** Per-socket token bucket `%{tokens, last_refill}` in assigns (`init_rate_bucket/0`, `take_rate_token/1`); refills by elapsed monotonic time at `limit`/`window_ms`, spends 1/query, empty → inline error, no Task. `Config.rate_limit()`, no new dep.
- [x] **T5.3** Tests: over-long prompt → `#query-error` "too long"; within-max accepted; 2nd rapid query (limit:1) → `#query-error` "too quickly". `has_element?/3` (ID + text). Config overrides safe (only DashboardLive reads them; same-module tests serialize).

**Verify:** `mix test test/live/dashboard_live_test.exs`

---

## Phase 6 — Test gaps, cleanup, full verification `[test]`

- [x] **T6.1** Added `Dai.AI.ClientBehaviour` (Client `@behaviour`/`@impl`), `Config.ai_client/0` (default `Dai.AI.Client`), `QueryPipeline.run/3` `client:` opt override (avoids global-config race). Mox dep + `ClientMock` in test_helper. `client_test.exs` (no-key path + behaviour conformance) + 3 run/3 end-to-end tests (happy/error/clarification).
- [x] **T6.2** New `system_prompt_test.exs` — scope section present only with scope, includes `table.column`, embeds schema + optional description. (Value not redacted: it's the tenant's own id, and the AI needs it to write the filter.)
- [x] **T6.3** Replaced vacuous suggestion test with two deterministic `render_component(empty_state)` tests (present→`#schema-suggestions` + text; absent→empty). Avoids racy persistent_term seeding.
- [x] **T6.4** LazyHTML `from_document`/`from_fragment` + `query` (v0.1.10 API, not parse/find) for table-grid + table-detail assertions; added `id="explorer-detail"` for an ID-based detail selector.
- [x] **T6.5** `Dai.AI.Component.component_type/0` `@type`; `Result.t()` references it (`Component.component_type() | :clarification | ...`), removing the duplicated atom union.
- [x] **T6.6** Added `{:mox, "~> 1.1", only: :test}` + `{:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}`; `precommit` alias now runs `deps.audit` before `test`.

**Verify (full):** `mix precommit` — ✅ GREEN: compile (warnings-as-errors) + deps.unlock --unused + format + **deps.audit ("No vulnerabilities found")** + **171 tests, 0 failures**.

**Security dep bumps (surfaced by the new `deps.audit`):** bandit 1.10.4→1.11.1 (3 DoS advisories), phoenix 1.8.5→1.8.7 (long-poll memory), postgrex 0.22.0→0.22.2 (**channel-name SQL injection**), + transitive (plug, thousand_island, db_connection, decimal 2.3→2.4, jason). One documented ignore: GHSA-rhv4-8758-jx7v (decimal DoS, only patched in 3.0, incompatible with current ecto/postgrex) — scoped via `--ignore-advisory-ids`.

---

## Risks & self-check (deep)

1. **What could break existing behavior?** Adding `user_token` as a required first arg to `Folders.*` is a breaking signature change across the context + LiveView; the migration makes `user_token` `NOT NULL` so existing dev rows need backfill (demo data — `mix ecto.reset` acceptable). All folder handle_events must be updated together or compilation fails (good — compiler enforces completeness).
2. **What's the riskiest assumption?** That `SET TRANSACTION READ ONLY` + `statement_timeout` on the *host's* repo is acceptable — it temporarily constrains that pooled connection for the txn only (`SET LOCAL`), so it's safe, but the dedicated `:readonly_repo` is the recommended production path. RLS enforcement depends on the host actually writing policies; the programmatic `:scope_violation` check is the fallback when they haven't.
3. **What did I not research?** Whether any host app already calls `Dai.Folders` functions directly (external API break). Mitigation: these are library-internal today (only DashboardLive calls them); document the signature change in CHANGELOG.

## Iron Law compliance
- Result tuples throughout; `with`/`case` for validation chains; no `String.to_atom` on user input; scope GUC parameterized (`$1`); no `IO.inspect`; structured `Logger.warning(..., key: val)`; constants as config/module attrs; LazyHTML ID-based test assertions.

## Out of scope (deferred, not security-critical)
- N+1 `save_layouts` upsert, `mount` double-query, boot-time blocking Claude call, GridBridge tests, scaffold dep scoping (`bandit`/`swoosh`/etc.) — tracked in the audit report; address in a separate perf/packaging pass.
