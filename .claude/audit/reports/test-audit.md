# Test Audit: Dai Project

**Date:** 2026-06-02
**Suite baseline:** 117 tests, 0 failures, ~1s

---

## Test Health Score: 68 / 100

The suite has solid coverage of the core data pipeline (PlanValidator, SqlExecutor, ResultAssembler, QueryPipeline) and context layers (Folders, DashboardLayout, DashboardPreferences). LiveView integration is structurally present. The main drags on the score are: the AI client has zero test isolation (no mock/behaviour wrapper), the recently-added `query_scope` feature is entirely untested, several pure-logic modules have no tests, and the push_card/dashboard_live tests use raw `html =~` string matching instead of LazyHTML selectors.

---

## 1. Coverage Gaps

### Critical gap — AI Client (`lib/dai/ai/client.ex`)

`Dai.AI.Client` calls the live Anthropic API at `https://api.anthropic.com/v1/messages`. There is **no test file for this module** and no Mox behaviour wrapping it. All pipeline tests that go through `QueryPipeline.run/3` (the top-level entry point, not `run_from_plan/2`) would hit the real API or silently skip the test path entirely. The query pipeline tests only call `run_from_plan/2`, bypassing `Client` entirely.

**Recommendation:** Define a `Dai.AI.ClientBehaviour` (`@callback generate_plan/3`, `@callback send_messages/2`), wrap the real implementation to call through the behaviour, register a `Mox.defmock(Dai.AI.MockClient, for: Dai.AI.ClientBehaviour)`, and add a `client_test.exs` that tests JSON parse logic (parse_response path) and error handling. This would also unlock testing `QueryPipeline.run/3` end-to-end without hitting the network.

**Files:** `lib/dai/ai/client.ex` — no corresponding test file exists.

### Critical gap — `query_scope` feature untested (`lib/dai/config.ex`, `lib/dai/ai/plan_validator.ex`)

`Config.query_scope/0` and `PlanValidator.warn_if_missing_scope/1` were added in commit `9b02af1`. No test in `plan_validator_test.exs` or `config_test.exs` exercises the `query_scope` configuration path. The `warn_if_missing_scope` function silently logs a warning when the scope column is absent — this is a security-adjacent feature (mandatory WHERE clause injection) that deserves explicit test coverage.

**Recommendation:** Add tests to `plan_validator_test.exs`:
- When `query_scope` is configured with `%{column: "org_id"}` and the SQL contains `org_id`, no warning is logged.
- When `query_scope` is configured and the SQL omits `org_id`, a Logger warning is emitted (use `ExUnit.CaptureLog`).
- `config_test.exs` should test `Config.query_scope/0` returns `nil` by default and the configured map when set.

**Files:** `lib/dai/ai/plan_validator.ex` lines 48–57, `lib/dai/config.ex` lines 51–54.

### Gap — `Dai.AI.SystemPrompt` (`lib/dai/ai/system_prompt.ex`)

No test file. The prompt construction logic (scope injection, action section inclusion, schema formatting) is pure-function territory that is straightforward to unit test.

**Recommendation:** Add `test/dai/ai/system_prompt_test.exs` covering: prompt contains schema context string; with `scope:` option the scope constraint text is included; without actions `ActionRegistry.prompt_section/0` returns empty; the `needs_clarification` instruction is present.

### Gap — `Dai.GridBridge` (`lib/dai/grid_bridge.ex`)

No test file. `result_to_card/2` has branching logic (ok vs error tuple) and `save_panel_sizes/3` mutates assigns. The push_card_test.exs tests `DashboardComponents.result_card/1` rendering directly but does not test the `GridBridge` wrapper.

**Recommendation:** `GridBridge.result_to_card/2` is pure (no socket side effects for the conversion logic) and can be tested with `ExUnit.Case, async: true`. Add `test/dai/grid_bridge_test.exs`.

### Gap — `Dai.SchemaExplorerComponents`, `Dai.SidebarComponents`, `Dai.DashboardComponents` (chart card types)

`push_card_test.exs` tests error, kpi_metric, data_table, and clarification renders but not chart cards (bar_chart, line_chart, pie_chart, action_confirmation). `DashboardComponents` has no direct test for chart renders.

**Recommendation:** Extend `push_card_test.exs` (or add `dashboard_components_test.exs`) to cover at least one chart card type and the `action_confirmation` card type.

### Gap — `Dai.Schema.Discovery` (`lib/dai/schema/discovery.ex`)

No test file. Schema discovery uses both `:application.get_key` and `:code.all_loaded()` — this branching logic should be smoke-tested.

---

## 2. Test Quality Issues

### `async: false` without Mox global mode justification

`plan_validator_test.exs` line 2 and `action_registry_test.exs` line 2 use `async: false`. Both tests use `Application.put_env/3` (which modifies global application env) — this is a legitimate reason for `async: false`. However, both tests restore state via `on_exit`, so they could be made `async: true` if `Application.put_env` were replaced with explicit option passing or if the functions under test accepted the config value as a parameter. Not a blocker, but worth noting.

### Raw `html =~` string matching in LiveView tests (project convention violation)

The project CLAUDE.md specifies: "HTML assertions: LazyHTML selectors. Test element IDs, not raw HTML content." The following tests violate this:

- `dashboard_live_test.exs` lines 41–43: `assert html =~ "users"` / `"plans"` / `"subscriptions"` — these should assert against `#schema-tables` child elements via LazyHTML.
- `dashboard_live_test.exs` lines 153–154: `assert html =~ "email"` / `assert html =~ "string"` — should use `has_element?(view, "#explorer-focus [data-column='email']")` or similar.
- `push_card_test.exs`: All assertions use raw `html =~`. Since this is a non-LiveView component render helper test, LazyHTML could be used for more precise structural assertions (e.g., assert a specific element has the `phx-click` attribute rather than substring matching).

### `dashboard_live_test.exs` — conditional test logic

Lines 54–59 in `dashboard_live_test.exs`:
```elixir
if explorer.suggestions != [] do
  assert has_element?(view, "#schema-suggestions")
else
  refute has_element?(view, "#schema-suggestions")
end
```

This test passes trivially when suggestions are empty (always in CI with no API key). It provides no coverage guarantee. The test should either be tagged `@tag :requires_api` and skipped in CI, or the suggestions should be injected via mock/config to test both branches deterministically.

### `query_pipeline_test.exs` — missing `QueryPipeline.run/3` coverage

All three tests in `query_pipeline_test.exs` use `run_from_plan/2`, which skips the `Client.generate_plan/3` step. There is no test for `QueryPipeline.run/3` (the public entry point that host apps would actually call). Without a mocked client this is hard to test, which circles back to the missing behaviour/mock for `Dai.AI.Client`.

---

## 3. Security-Critical Path Assessment

### PlanValidator — adequate with one gap

The keyword blocklist tests cover INSERT, UPDATE, DELETE, DROP, TRUNCATE, ALTER and case-insensitive matching. Missing:

- `CREATE` keyword — present in the regex `@forbidden_pattern` but not tested with an explicit case.
- `EXEC`/`EXECUTE` — in the regex but not tested.
- SQL comment injection: `SELECT * FROM users -- DROP TABLE users` — the current regex would not catch this (the DROP is after `--`), but there is no test documenting this known limitation.
- Semicolon-terminated injection: `SELECT 1; DELETE FROM users` — not tested. The regex matches `DELETE` here and would reject it, but there is no explicit test.

**Recommendation:** Add a test group "injection attempts" to `plan_validator_test.exs` covering EXEC, CREATE, comment bypass attempt (document expected behavior), and semicolon injection.

### SqlExecutor — no injection test for scope bypass

`sql_executor_test.exs` tests valid queries and a bad table name but not scope-bypass attempts. Since `SqlExecutor` receives pre-validated SQL, this is downstream of `PlanValidator`, but a note in the test file documenting the trust model would be valuable.

### AI Client — no test isolation (see Coverage Gaps above)

---

## 4. Test Data / Infrastructure

- No factory library (ExMachina) — tests create data directly via context functions. This is fine for a library with minimal schema complexity.
- Sandbox is properly configured: `Ecto.Adapters.SQL.Sandbox.mode(Dai.Repo, :manual)` in `test_helper.exs`, `start_owner!` in `DataCase.setup_sandbox/1`.
- No Mox usage anywhere in the test suite — acceptable given the AI client is not behind a behaviour, but blocks proper AI client testing.

---

## 5. Flaky-Test Risk

- No `Process.sleep` usage found — clean.
- No time-dependent assertions found.
- The conditional suggestion test (dashboard_live_test.exs lines 54–59) is a reliability risk: always passes vacuously in CI.
- `action_registry_test.exs` and `plan_validator_test.exs` use `Application.put_env` with `async: false` — correctly sequenced, low risk.

---

## Summary of Recommendations (Priority Order)

1. **[High]** Add `Dai.AI.ClientBehaviour` + Mox mock, add `client_test.exs`, enable `QueryPipeline.run/3` testing without live API calls.
2. **[High]** Add `query_scope` tests to `plan_validator_test.exs` and `config_test.exs` — this is a new security-adjacent feature with zero test coverage.
3. **[Medium]** Add injection-attempt tests to `plan_validator_test.exs` (EXEC, CREATE, semicolons).
4. **[Medium]** Add `system_prompt_test.exs` for prompt construction logic.
5. **[Medium]** Fix conditional suggestion test — make deterministic via config injection or skip tag.
6. **[Low]** Replace `html =~` assertions in LiveView tests with `has_element?` / LazyHTML selectors per project convention.
7. **[Low]** Add `grid_bridge_test.exs` for `result_to_card/2` branching logic.
8. **[Low]** Extend `push_card_test.exs` to cover chart card types and `action_confirmation`.
