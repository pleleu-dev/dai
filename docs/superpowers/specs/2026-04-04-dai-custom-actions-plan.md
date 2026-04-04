# Dai Custom Actions — Implementation Plan

## Context

Dai is a read-only NL dashboard. We're adding a generic action system so host apps can register custom actions (e.g., "approve organization", "send notification") that Claude can propose and users can confirm within the Dai dashboard. Full spec: `docs/superpowers/specs/2026-04-04-dai-custom-actions-design.md`.

## Phase 1: Core Library (Dai)

### Step 1: `Dai.Action` behaviour
- **Create** `lib/dai/action.ex`
- Define callbacks: `id/0`, `label/0`, `description/0`, `target_table/0`, `target_key/0`, `confirm_message/1`, `execute/2`
- Add `@type` specs for `target` (map) and `params` (map)

### Step 2: `Dai.Config.actions/0`
- **Edit** `lib/dai/config.ex`
- Add `def actions, do: Application.get_env(:dai, :actions, [])`

### Step 3: `Dai.AI.ActionRegistry`
- **Create** `lib/dai/ai/action_registry.ex`
- `all/0` — calls each configured module's callbacks, returns list of metadata maps
- `lookup/1` — finds module by string id, returns `{:ok, module}` or `:error`
- `prompt_section/0` — generates system prompt fragment describing available actions

### Step 4: Extend `Dai.AI.SystemPrompt`
- **Edit** `lib/dai/ai/system_prompt.ex`
- `build/1` checks `ActionRegistry.all/0`; if non-empty, appends the actions section to the prompt
- Actions section tells Claude: when to return action plans, the JSON format, that SQL must be SELECT

### Step 5: Extend `Dai.AI.PlanValidator`
- **Edit** `lib/dai/ai/plan_validator.ex`
- Add `validate(%{"type" => "action"} = plan)` clause
- Validates: `action_id` exists in registry, `sql` passes forbidden-keyword check
- Returns `{:ok, plan}` or `{:error, reason}`

### Step 6: Extend `Dai.AI.Result`
- **Edit** `lib/dai/ai/result.ex`
- Add `:action_confirmation` and `:action_result` to the type union
- Add optional fields: `action_id`, `action_targets`, `action_params`
- Add `action_confirmation/4` and `action_success/2` and `action_error/2` constructors

### Step 7: Extend `Dai.AI.QueryPipeline`
- **Edit** `lib/dai/ai/query_pipeline.ex`
- Add `run_from_plan(%{"type" => "action"} = plan, prompt)` clause
- Flow: validate action plan → run SELECT via SqlExecutor → build `:action_confirmation` result
- Reuse existing `SqlExecutor.execute/1` for the SELECT

### Step 8: `Dai.AI.ActionExecutor`
- **Create** `lib/dai/ai/action_executor.ex`
- `execute/3` — takes action module, target row map, params map
- Calls `module.execute(target, params)`
- Returns `{:ok, result}` or `{:error, reason}`

## Phase 2: UI (Dai)

### Step 9: Confirmation card component
- **Edit** `lib/dai/dashboard_components.ex`
- Add `card_body` clause for `:action_confirmation` type
- Renders: title/description, mini data table of targets, `confirm_message/1` text, Confirm + Cancel buttons
- Confirm button: `phx-click="confirm_action"` with `phx-value-result-id`

### Step 10: Action result card component
- **Edit** `lib/dai/dashboard_components.ex`
- Add `card_body` clause for `:action_result` type
- Success: green card with check icon and summary
- Error: red card with error message (no retry button — mutations shouldn't auto-retry)

### Step 11: DashboardLive event handlers
- **Edit** `lib/dai/dashboard_live.ex`
- Add `pending_actions` map to mount assigns
- When streaming an `:action_confirmation` result, also store it in `pending_actions`
- Add `handle_event("confirm_action", %{"result-id" => id}, socket)`:
  - Look up pending action, call `ActionExecutor.execute/3`
  - Replace confirmation card with `:action_result` card in stream
  - Remove from `pending_actions`
- Cancel uses existing `"dismiss"` event

## Phase 3: Host App (Maildefender — separate repo)

### Step 12: Create action modules
- **Create** `lib/maildefender/dai_actions/approve_organization.ex`
- **Create** `lib/maildefender/dai_actions/mark_lead_contacted.ex`
- **Create** `lib/maildefender/dai_actions/send_notification.ex`
- **Create** `lib/maildefender/dai_actions/update_brand_contact.ex`
- Each ~20 lines implementing `Dai.Action` behaviour
- Each delegates to the appropriate `Organizations` context function

### Step 13: Register actions in config
- **Edit** `config/config.exs`
- Add `actions: [...]` to existing `:dai` config block

## Phase 4: Tests

### Step 14: Unit tests for Dai library
- **Create** `test/dai/ai/action_registry_test.exs` — test `all/0`, `lookup/1`, `prompt_section/0` with mock action modules
- **Create** `test/dai/ai/query_pipeline_action_test.exs` — test pipeline branching with action plans
- **Create** `test/dai/ai/action_executor_test.exs` — test execute/3 with mock action module

### Step 15: Maildefender integration tests (separate repo)
- **Create** `test/maildefender/dai_actions/approve_organization_test.exs` — test execute/2
- **Create** `test/maildefender_web/live/admin/dai_actions_test.exs` — LiveView test: mount → action prompt → confirm → verify

## Verification

1. `mix test` — Dai library tests pass
2. `mix precommit` — full quality check
3. In Maildefender repo: `mix test` after updating Dai dep
4. Manual E2E: `mix dev` (from Maildefender) → `/admin/explore` → "approve the UPS organization" → confirm → verify

## Key Files

| File | Action |
|------|--------|
| `lib/dai/action.ex` | Create |
| `lib/dai/ai/action_registry.ex` | Create |
| `lib/dai/ai/action_executor.ex` | Create |
| `lib/dai/config.ex` | Edit (add `actions/0`) |
| `lib/dai/ai/system_prompt.ex` | Edit (append actions section) |
| `lib/dai/ai/plan_validator.ex` | Edit (add action plan clause) |
| `lib/dai/ai/query_pipeline.ex` | Edit (add action branching) |
| `lib/dai/ai/result.ex` | Edit (add action types + fields) |
| `lib/dai/dashboard_live.ex` | Edit (pending_actions, confirm event) |
| `lib/dai/dashboard_components.ex` | Edit (confirmation + result cards) |
