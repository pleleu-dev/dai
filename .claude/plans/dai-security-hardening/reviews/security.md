# Security Audit: Dai Security-Hardening

## Executive Summary

The five hardening changes are competently implemented and materially improve
the posture (read-only execution boundary, tenant scoping/IDOR fix, error
redaction, rate limiting, prompt cap). I found **no BLOCKERs** in the new code.
The design decisions (D7/D8, interpolated integer timeout, GUC parameterization)
are correctly implemented. The main residual risks are the inherent weakness of
`String.contains?`-based scope enforcement (correctly framed as defense-in-depth)
and multi-statement / read-only-bypass edges that depend on the host honoring the
recommended `:readonly_repo` role. Severities below reflect that the in-engine
read-only transaction + host RLS are the real boundaries.

## Findings

### 1. Scope enforcement via `String.contains?` is bypassable — WARNING (accept as DiD)
`plan_validator.ex:77` — `String.contains?(sql, column)` passes if the column
name appears *anywhere*: in a comment (`-- org_id`), a string literal
(`WHERE name = 'org_id'`), or as a substring of another identifier
(`organization_id_other`). An AI (or prompt-injected) plan could include the
token without actually filtering. This is acceptable **only because** RLS+GUC is
the real control — but the moduledoc claims "a host without RLS policies still
gets isolation from this check," which overstates it. **Fix:** soften the doc
claim, OR require the column appear in a WHERE/JOIN context (still heuristic), OR
best: rely on the GUC + mandate RLS and downgrade this to a warning-log only.
Keep severity WARNING; do not advertise it as a hard isolation guarantee.

### 2. Read-only transaction bypass surface — WARNING (mitigated by D7 + role)
`sql_executor.ex:35,39` — `SET LOCAL transaction_read_only = on` correctly blocks
INSERT/UPDATE/DELETE/DDL and data-modifying CTEs at the engine level. Residual
gaps that `transaction_read_only` does **not** stop: `SELECT pg_read_file(...)`,
`COPY ... TO/FROM PROGRAM`, `lo_*` large-object functions, and SELECTs that call
volatile/SECURITY DEFINER functions with side effects. `repo.query(sql)` sends a
single simple-query string; libpq simple query *can* contain multiple
`;`-separated statements, but `transaction_read_only` + the validator blocklist
blunt the write paths. **Fix (already the recommendation):** strongly steer hosts
to `:readonly_repo` with `GRANT SELECT` only and `REVOKE` on `pg_read_file`/`COPY`;
consider documenting `SET LOCAL search_path` pinning so the SQL can't resolve a
shadowed function. Severity WARNING — the design is sound, the role is the fix.

### 3. statement_timeout interpolation — SAFE (verified)
`sql_executor.ex:36` — `#{timeout}` comes from `Config.statement_timeout_ms/0`,
host config, never user input; `SET` can't bind params. Not injectable. The
`@spec :: pos_integer()` and default make it well-typed. No action. (Minor
SUGGESTION: a defensive `is_integer/1` assert would harden against a host
mis-configuring a string, which would then interpolate raw — theoretical.)

### 4. GUC scope value — SAFE (verified)
`sql_executor.ex:68` — `set_config('dai.scope_value', $1, true)` binds the value
as `$1`. Injection-safe even for adversarial scope values. Correct per D8.

### 5. Folders IDOR fix — SOLID; one substantive note
- All reads (`list_folders`, `list_saved_queries`, `get_*!`) filter by
  `user_token`. Ownership-mutating paths use `fetch_owned/3` → `{:error, :not_found}`. Good.
- `create_folder`/`create_saved_query` do `Map.put(attrs, :user_token, user_token)`
  (folders.ex:35,73). Because `Map.put` runs **after** the caller's attrs, a
  caller cannot override `user_token` even though the changeset casts it. Safe.
  Caveat: this relies on `attrs` being a map with that exact key shape; all
  call sites pass maps. OK.
- **WARNING — unscoped folder_id on save:** `save_query` (dashboard_live.ex:331)
  forwards client-supplied `folder_id` into `create_saved_query` without
  verifying the folder belongs to `user_token`. Impact is limited: the row is
  stamped with the attacker's own `user_token`, and `list_saved_queries` filters
  by both `user_token` AND `folder_id`, so it can't surface in a victim's folder
  — no cross-tenant read/write. But it creates a saved_query pointing at another
  tenant's folder_id (FK only checks existence). **Fix:** call
  `fetch_owned(Folder, user_token, folder_id)` before insert; reject otherwise.
  Severity WARNING (data-integrity, not a leak).
- `update_folder/2` and `update_saved_query/2` take a struct and re-cast
  `:user_token`; a caller could theoretically pass `%{user_token: other}` to
  reassign ownership. Current call sites only pass `%{name:}`/`%{title:}`, so not
  reachable — SUGGESTION: drop `:user_token` from the update changeset cast or
  use a separate changeset to make tenant reassignment structurally impossible.

### 6. Auth / token trust model — acceptable, documented
`dashboard_live.ex:274` — session token preferred over `connect_params`
(client-controlled localStorage) over random fallback. Correct precedence. The
`connect_params` path is an *unauthenticated* tenant claim: any client can send
`dai_user_token: "victim"` and impersonate that tenant's folders **iff** the host
did not wire a session `user_token`. This is the documented single-tenant
fallback, so WARNING, not BLOCKER — but the router/moduledoc must make it
unmistakable that **multi-tenant hosts MUST provide `user_token:`** and that the
connect_params fallback offers zero isolation. Confirm the router warning says
this in those terms. Random fallback uses `strong_rand_bytes(16)` — safe.

### 7. Error leakage — CLEAN
`result.ex:79` returns a generic message for `{:query_failed, _}`; raw Postgres
detail is logged only at `sql_executor.ex:54`. `:scope_violation` message is
generic. No SQL or schema names reach the client. Verified no other path passes
`postgres_message/1` output to `Result`. One residual: `error_message(reason)
when is_binary(reason)` (result.ex:82) returns the binary verbatim — ensure no
internal binary reason flows here from new code; current new reasons are atoms or
`{:query_failed, _}`. OK.

### 8. Rate limit & prompt cap — per-socket only, known limitation — WARNING
`dashboard_live.ex:618-621` — bucket lives in socket assigns. An attacker can
open N WebSocket connections to get N× the limit, and each reconnect resets the
bucket to full. Likewise the prompt cap is per-event only. This throttles honest
users and accidental loops but is **not** a real anti-abuse control against a
determined client. Acceptable as a first layer; **document** it and recommend a
shared limiter (Hammer/ETS keyed by `user_token` or remote IP) plus an
endpoint-level limit for production. Severity WARNING. `String.length/1` (line
588) counts graphemes not bytes while `Config` doc says "bytes" — cosmetic
mismatch, SUGGESTION to align doc or use `byte_size/1`.

### 9. Migration — minor
`20260602194702_*.exs` — backfills NULLs to sentinel `'legacy'` before NOT NULL.
All pre-existing demo rows collapse into one shared `'legacy'` tenant; fine for a
dev/demo dataset, but note any real pre-existing host data would become
cross-readable under that single token. SUGGESTION: document that hosts with
existing rows must remediate `'legacy'` before exposing multi-tenant.

## Security Posture

- **SQL Injection:** ✅ Scope GUC + timeout safe; user SQL is AI-generated and run
  read-only. The AI-SQL execution model itself is the risk, mitigated by D7/role.
- **Authorization (IDOR):** ⚠️ Core fix solid; gaps: unscoped `folder_id` on save (#5),
  `update_*` re-casting `user_token` (#5), connect_params tenant spoofing (#6).
- **Tenant scope enforcement:** ⚠️ `String.contains?` is defense-in-depth only (#1).
- **Read-only boundary:** ✅/⚠️ Correct; full safety needs `:readonly_repo` role (#2).
- **Error leakage:** ✅ Clean (#7).
- **Rate limiting:** ⚠️ Per-socket, bypassable by reconnect/multi-socket (#8).

Checked secrets (none in new code), XSS/`raw`, `String.to_atom`,
`binary_to_term`: all clean in the changed files.

## Recommendations (prioritized)
1. Verify `folder_id` ownership in `save_query` before insert (#5).
2. Remove `:user_token` from update changesets / use dedicated changeset (#5).
3. Soften the moduledoc claim that the `String.contains?` check gives isolation
   without RLS; lead hosts to RLS + `:readonly_repo` (#1, #2).
4. Make the multi-tenant requirement for `user_token:` unmissable in router docs;
   warn that connect_params fallback = no isolation (#6).
5. Document the per-socket rate-limit limitation; recommend a shared limiter (#8).
6. Reconcile `String.length` vs documented "bytes" for the prompt cap (#8).

## Tools to Recommend (run manually — no Bash here)
- `mix sobelow --exit medium`
- `mix deps.audit`
- `mix hex.audit`
