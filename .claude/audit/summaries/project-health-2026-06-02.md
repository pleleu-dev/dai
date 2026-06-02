# Dai — Project Health Audit

**Date:** 2026-06-02 · **Branch:** main @ `26a3a57` · **Mode:** `--full` (5 parallel specialist auditors)

---

## Executive Summary

> ⚠️ **OVERALL GRADE: D (61 / 100) — flagged CRITICAL by override.**
> The codebase is *engineered* well (clean compile, 117 green tests, sound async/library architecture) but is *unsafe by design*: it executes LLM-generated SQL against the host database guarded only by a regex blocklist, with no tenant isolation and no authentication on the standalone route. The numeric score is dragged into "Critical" by the Security category, and the [Critical Issues Override](#) (security vulnerability present) applies regardless of the weighted average.

Pulse check (run before the agents): `mix compile --warnings-as-errors` ✅ clean · `mix test` ✅ 117 tests / 0 failures in ~1s · 3 xref cycles, all benign.

### Health Scorecard

| Category | Score | Grade | Headline |
|---|---|---|---|
| 🏛️ Architecture | **74** | C | Solid library boundary & pipeline; Folders lack tenant isolation; `DashboardLive` (584 LOC) nearing god-module |
| ⚡ Performance | **74** | C | Async design is good; unbounded AI SQL, N+1 layout upsert, boot-time blocking API call |
| 🔒 Security | **28** | **F** | LLM→SQL execution unsafe; tenant scope is advisory-only; unauthenticated route + token; Folders IDOR |
| 🧪 Tests | **68** | D | Good fast suite; public pipeline entry (`QueryPipeline.run/3`) & `query_scope` untested; Client not mocked |
| 📦 Dependencies | **72** | C | No CVEs/unused deps; 7 scaffold-only deps forced onto host apps; no vuln scanner |

**Weighted overall** = 74·0.20 + 74·0.25 + 28·0.25 + 68·0.15 + 72·0.15 = **61.3 → D**, escalated to **CRITICAL** by security override.

---

## 🔴 Critical Findings (fix before any production / host-app use)

These cluster into **two root problems**. Several were independently flagged by 2+ auditors (noted inline).

### Cluster A — The SQL execution trust model is broken
The whole value proposition (NL → SQL → run on host DB) currently has no real safety boundary.

1. **Tenant `query_scope` is advisory-only — no enforcement.** *(Security #1 + Tests confirm untested)*
   The "mandatory WHERE clause injection" added in `9b02af1` lives entirely in the Claude *prompt* (`system_prompt.ex:76`). `PlanValidator.warn_if_missing_scope/1` (`plan_validator.ex:48`) only **logs a warning** and runs the SQL anyway. Trivially defeated by prompt injection or the model simply omitting the clause → **cross-tenant data exfiltration**. The test suite never exercises this path at all.

2. **SQL blocklist is bypassable.** *(Security #2 + Performance HIGH)*
   A single deny-regex (`plan_validator.ex:8`) cannot stop `pg_read_file` / `pg_ls_dir` / `COPY` / CTEs / stacked statements. Even a "pure SELECT" can read files and credentials. There is no read-only DB role and no LIMIT *clamp* — `ensure_limit/1` only appends a LIMIT when absent, so a model-supplied `LIMIT 5000000` passes through, and there is **no statement timeout / row ceiling** (`sql_executor.ex:4`).

3. **Raw Postgres errors leaked to the client.** *(Security #5)*
   `sql_executor.ex:16` → `result.ex:76` surface DB error text to the UI = schema disclosure + blind-SQL oracle.

> **Single highest-impact remediation:** run all generated SQL through a dedicated **least-privilege, read-only Postgres role inside a read-only transaction** with `statement_timeout` set, and enforce tenant isolation with **Postgres Row-Level Security**, not the LLM prompt. This neutralizes #1, #2, and most of #3 at once.

### Cluster B — Missing authn/authz on user-scoped data
4. **Unauthenticated dashboard + unauthenticated `user_token`.** *(Security #3)*
   Standalone route (`dai_web/router.ex:19`) has no auth plug; `user_token` comes from client connect params with a random fallback (`dashboard_live.ex:204`). Supply someone else's token → read/write their data.

5. **Folders & saved queries are fully global (IDOR).** *(Security #4 + Architecture #1 — both auditors independently)*
   `Dai.Folders.Folder` / `SavedQuery` have **no `user_token` column**. `list_folders/0` returns everyone's folders; `delete_folder_by_id/1` and `rename_folder/2` do a bare `repo().get(Folder, id)` with no ownership check — any session can rename/delete another user's folder by guessing a UUID. Notably, `DashboardLayout` and `DashboardPreferences` *do* scope by `user_token` — the pattern exists, it was just never applied to Folders.

---

## 🟠 High / Medium Findings

| # | Area | Finding | Location |
|---|---|---|---|
| 6 | Perf | No prompt-size limit or rate limiting on NL→SQL event → cost-amplification / DoS on paid Claude API | `dashboard_live.ex` event |
| 7 | Perf | N+1 upsert: `save_layouts/2` does SELECT-then-INSERT/UPDATE per card (2N queries) on every drag/resize | `dashboard_layout.ex:64` → use `insert_all` + `on_conflict` |
| 8 | Perf + Arch | Unconditional DB reads in `mount` (prefs + layouts + folders) run on **both** dead & connected render → ~6 queries/load | `dashboard_live.ex:204/213-214,229` → guard behind `connected?/1` |
| 9 | Perf | Boot-time **blocking** Claude API call in `start_link` (up to 30s, crash-loops if API down) | `schema_explorer.ex:18` → defer to lazy/async |
| 10 | Tests | `QueryPipeline.run/3` (public entry point) has **zero coverage** — Client makes real HTTP calls, no behaviour/mock; tests sidestep via `run_from_plan/2` | add `Dai.AI.ClientBehaviour` + Mox + `client_test.exs` |
| 11 | Tests | `query_scope` feature entirely untested (security-adjacent) | add `CaptureLog` test asserting warning fires |
| 12 | Tests | PlanValidator injection-attempt tests missing (comment bypass, `;` stacking, `EXEC`/`CREATE`) | `plan_validator_test.exs` |
| 13 | Deps | **7 scaffold-only runtime deps forced onto host apps**: `bandit`, `dns_cluster`, `phoenix_live_dashboard`, `telemetry_metrics`, `telemetry_poller`, `gettext`, `swoosh` — used only in `standalone?` branch / `lib/dai_web/`. Scope `only: [:dev,:test]` / `runtime: false` / `optional: true` | `mix.exs` deps |
| 14 | Arch | `Dai.AI.Component` (declared single source of truth) duplicated: 5 atom types re-hardcoded in `result.ex:7-11` `@type` union — compiler won't catch drift | derive from `Component` |
| 15 | Arch | `DashboardLive` 584 LOC, 26 `handle_event` clauses across 4 concerns — extract folder block (~120 LOC, 10 events) into `Dai.FolderEventHandler` | `dashboard_live.ex` |

---

## 🟡 Low Findings

- **Deps:** No vuln scanner — `mix deps.audit` fails (`mix_audit` absent). Add `{:mix_audit, "~> 2.1", only: [:dev,:test], runtime: false}`; `mix hex.audit` is clean. *(scoring −6)*
- **Deps:** `live_charts ~> 0.4.0` is pre-1.0, single-purpose, on the AI-output render path, and its `phoenix_live_view ~> 1.0.0` cap is **why `override: true` is needed** — undocumented transitive-conflict workaround in `mix.exs`. Add a comment; drop the override once live_charts supports LV 1.1.
- **Deps:** Only minor/patch drift (phoenix 1.8.5→1.8.7, req 0.5.17→0.5.18, etc.) — nothing >1 major behind.
- **Perf:** Missing `index(:dai_folders, [:position])` (ordered-by on every mount); unbounded `Task.async` fan-out in `load_all_folder_queries` (50 queries = 50 concurrent API calls); no `retry:` on the Req client.
- **Tests:** Conditional suggestion test (`dashboard_live_test.exs:54-59`) is vacuously true in CI (no API key → suggestions always empty). `SystemPrompt` and `GridBridge` have no test files. Raw `html =~` substring matching used where convention requires LazyHTML ID selectors (`dashboard_live_test.exs:41-43,153-154`).

### ✅ Clean areas (one line each)
XSS (HEEx auto-escaping, no `raw/1`) · CSRF + secure headers · secrets from env in `runtime.exs` · `:persistent_term` written once at boot (no footgun) · demo migrations index all FKs · AI client runs off the LiveView process · zero `DaiWeb.*` leakage in `lib/dai/` · all 3 xref cycles benign · no unused/retired deps.

---

## Action Plan

### 🚑 Immediate (security — do before production or shipping to a host app)
1. **Read-only DB role + read-only transaction + `statement_timeout`** for all generated SQL (kills #1/#2/#3 SQL risks). Clamp `LIMIT` to `Component.default_limit`.
2. **Enforce tenant isolation with Postgres RLS**, not the prompt; keep the prompt hint as defense-in-depth.
3. **Add `user_token` to `Folders.Folder` + `SavedQuery`**, scope every query, validate ownership before mutate (#5).
4. **Authenticate the dashboard route** and validate/sign `user_token` (#4); stop leaking raw DB errors to the client (#3).
5. **Rate-limit + size-cap** the NL→SQL event (#6).

### 📅 Short-term (correctness, testability)
6. Introduce `Dai.AI.ClientBehaviour` + Mox → unlock testing `QueryPipeline.run/3`; add `query_scope` and PlanValidator injection tests (#10–12).
7. Fix the `mount` double-query (`connected?/1` guard) and the `save_layouts` N+1 (`insert_all`/`on_conflict`); defer the boot-time Claude call (#7–9).
8. Add `mix_audit` to `precommit`; document/scope the `phoenix_live_view` override.

### 🌱 Long-term (maintainability, packaging)
9. **Scope the 7 scaffold-only deps** so the library doesn't force `bandit`/`swoosh`/`dns_cluster`/etc. onto host apps (#13) — the single biggest library-hygiene win.
10. Extract folder events out of `DashboardLive` (#15); derive component types from `Dai.AI.Component` (#14).

---

*Reports: `.claude/audit/reports/{arch-review,perf-audit,security-audit,test-audit,deps-audit}.md`. Scores are project-internal trend baselines — do not compare across projects.*
