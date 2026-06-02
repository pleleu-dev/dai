# Security Review: Dai Security Hardening

**Verdict: PASS WITH WARNINGS** — no BLOCKERs. All requirements met; several warnings worth addressing before the PR.

## Requirements Coverage (Plan dai-security-hardening)

`SUMMARY: 30 MET, 0 PARTIAL, 0 UNMET, 0 UNCLEAR`

All 7 audit findings (#1–#6, #14) and all 20 phase tasks (T0.1–T6.6) are implemented with file:line evidence. Both documented deviations — D7 (`SET LOCAL transaction_read_only = on`) and D8 (`set_config` GUC) — are implemented as specified, not missing. No divergences from the plan.

## Security Findings (security-analyzer)

No BLOCKERs. The read-only execution boundary, GUC parameterization, timeout interpolation, error redaction, and folders ownership scoping are all correctly implemented and verified injection-safe. Residual findings:

### Worth fixing (cheap, real)
1. **Unscoped `folder_id` on save** — WARNING — `dashboard_live.ex:331` `save_query` forwards a client-supplied `folder_id` into `create_saved_query` with no ownership check. **Not a cross-tenant leak** (the row is stamped with the caller's own `user_token`, and `list_saved_queries` filters on both keys, so it never surfaces for attacker or victim) — but it creates an orphaned saved_query pointing at another tenant's `folder_id`. Fix: `fetch_owned(Folder, user_token, folder_id)` before insert (ideally in `Folders.create_saved_query`).
2. **`update_folder/2` / `update_saved_query/2` re-cast `:user_token`** — SUGGESTION — not reachable from current call sites (only `%{name:}`/`%{title:}` passed), but structurally allows ownership reassignment. Drop `:user_token` from the update path (separate changeset or `cast` without it).

### Documentation accuracy (no code risk, but claims should match reality)
3. **Scope-check moduledoc overclaims** — `plan_validator.ex` — `String.contains?(sql, column)` is bypassable (column name in a comment / string literal / substring of another identifier). Correct as defense-in-depth, but the moduledoc claim that "a host without RLS still gets isolation" overstates it. Soften; lead hosts to RLS + `:readonly_repo`.
4. **connect_params trust** — `dashboard_live.ex` — the unauthenticated localStorage fallback lets any client claim a `user_token` when the host wires no session token. Documented, but the router docs must make it unmistakable that **multi-tenant hosts MUST pass `user_token:`** and that connect_params fallback = zero isolation.
5. **Per-socket rate limit is bypassable** — `Dai.RateLimiter` in socket assigns — N connections = N× limit, reconnect resets the bucket. Fine as a first layer; document the limitation and recommend a shared (Hammer/ETS) limiter keyed by `user_token`/IP for production.
6. **Migration `'legacy'` sentinel** — `20260602194702_*.exs` — pre-existing rows collapse into one shared `'legacy'` tenant. Fine for the demo dataset; document that hosts with real existing data must remediate before exposing multi-tenant.

### Read-only boundary depth (inherent, mitigated by recommended role)
7. **`transaction_read_only` doesn't stop `pg_read_file` / `COPY ... PROGRAM` / volatile-function side effects** — WARNING — only the recommended `:readonly_repo` `GRANT SELECT` role fully closes this. Already the documented prod path; consider adding a `REVOKE`/`search_path`-pinning note to the README.

### Verified SAFE / CLEAN
- statement_timeout interpolation (integer from config, not user input)
- scope GUC `set_config(..., $1, true)` parameterization
- error leakage (generic client messages, detail logged at boundary)
- secrets, XSS/`raw`, `String.to_atom`, `binary_to_term`

### Quick win
8. **`String.length/1` vs documented "bytes"** for the prompt cap — `Config.max_prompt_length/0` doc says "bytes" but the check counts graphemes. Align doc or use `byte_size/1`.

## Recommended manual checks
`mix sobelow --exit medium` · `mix deps.audit` (now in precommit) · `mix hex.audit`
