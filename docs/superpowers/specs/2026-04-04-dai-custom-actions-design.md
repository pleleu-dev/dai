# Dai Custom Actions

## Context

Dai is currently a read-only NL dashboard — every prompt generates a SELECT
query and a visualization. Users exploring Maildefender data through Dai
(`/admin/explore`) naturally want to act on what they find: approve an
organization, notify a lead, update brand contact info. Today they must leave
Dai and navigate to the relevant admin page to perform these actions.

This design adds a generic action system to the Dai library so host apps can
register custom actions that Claude can propose and users can confirm, all
within the Dai dashboard.

## Requirements

- **Generic Dai feature**: built into the library, not Maildefender-specific
- **Always confirm**: every action shows a confirmation card; user approves or
  cancels before execution
- **Query + single action**: Claude can run a SELECT to find targets, then
  propose one action on the results — two-step plan with one confirmation

## Design

### 1. Action Registration

Each action is a module implementing the `Dai.Action` behaviour:

```elixir
defmodule Dai.Action do
  @type target :: map()
  @type params :: map()

  @callback id() :: String.t()
  @callback label() :: String.t()
  @callback description() :: String.t()
  @callback target_table() :: String.t()
  @callback target_key() :: String.t()
  @callback confirm_message(target()) :: String.t()
  @callback execute(target(), params()) :: {:ok, term()} | {:error, term()}
end
```

`execute/2` always receives a **single target row** (a map). When a SELECT
returns multiple rows, the executor calls `execute/2` once per row.

Host apps register action modules in config:

```elixir
config :dai,
  actions: [
    Maildefender.DaiActions.ApproveOrganization,
    Maildefender.DaiActions.MarkLeadContacted,
    Maildefender.DaiActions.SendNotification,
    Maildefender.DaiActions.UpdateBrandContact
  ]
```

Example action module (~20 lines):

```elixir
defmodule Maildefender.DaiActions.ApproveOrganization do
  @behaviour Dai.Action

  def id, do: "approve_organization"
  def label, do: "Approve organization"
  def description, do: "Sets the organization's approved flag to true"
  def target_table, do: "organizations"
  def target_key, do: "id"
  def confirm_message(target), do: ~s(Approve organization "#{target["name"]}"?)

  def execute(target, _params) do
    org = Maildefender.Repo.get!(Maildefender.Organizations.Organization, target["id"])
    Maildefender.Organizations.approve_organization(org)
  end
end
```

### 2. Action Registry

New module `Dai.AI.ActionRegistry` reads `Dai.Config.actions/0` at call time:

- `all/0` — returns list of action module metadata
- `lookup/1` — finds action module by string id
- `prompt_section/0` — generates the system prompt fragment describing all
  available actions (id, label, description, target table/key)

### 3. System Prompt Extension

`Dai.AI.SystemPrompt.build/1` appends an "Available Actions" section when
actions are configured. This tells Claude:

- When to return an action plan vs a query plan
- The response format for action plans
- That the SQL must be a SELECT finding target rows with enough columns for
  user verification

Action prompt section template:

```
## Available Actions

When the user asks you to perform an action (not just view data), return an
action plan instead of a query plan.

Actions:
- {id}: {label}. {description}. Target: {target_table} (key: {target_key})

Action response format:
{"type": "action", "title": "...", "description": "...",
 "sql": "SELECT ... FROM {target_table} WHERE ...",
 "action_id": "{id}", "params": {}}

The SQL must be a SELECT that finds the target row(s). Include enough columns
for the user to verify the targets.
```

### 4. Plan Format

Claude returns one of three plan shapes:

**Query plan** (existing, unchanged):
```json
{"title": "...", "description": "...", "sql": "SELECT ...",
 "component": "bar_chart", "config": {...}}
```

**Action plan** (new):
```json
{"type": "action", "title": "Approve UPS", "description": "...",
 "sql": "SELECT id, name FROM organizations WHERE ...",
 "action_id": "approve_organization", "params": {}}
```

**Clarification** (existing, unchanged):
```json
{"needs_clarification": true, "question": "..."}
```

### 5. Pipeline Changes

`QueryPipeline.run/2` branches after `Client.generate_plan/2`:

```
plan["type"] == "action"?
  YES → validate SQL (SELECT only) + validate action_id exists in registry
      → run SELECT via SqlExecutor to find targets
      → build %Result{type: :action_confirmation} with target rows
      → render confirmation card (NO execution yet)

  NO  → existing path: PlanValidator → SqlExecutor → ResultAssembler
```

Safety: action plan SQL still passes through PlanValidator (must be SELECT).
The action is never auto-executed — only a confirmation card is produced.

New `Dai.AI.ActionValidator` (or extended `PlanValidator`):
- Validates `action_id` exists in ActionRegistry
- Validates SQL passes existing forbidden-keyword check
- Ensures SQL targets the correct table
- **No LIMIT enforcement** — action plans need all matching rows so users can
  verify every target before confirming

### 6. Result Struct Changes

New fields on `%Dai.AI.Result{}`:

```elixir
:action_id,       # string — which action was proposed
:action_targets,  # [map()] — row maps from the SELECT
:action_params    # map() — extra params for execute/2
```

New type values: `:action_confirmation`, `:action_result`

### 7. Confirmation UI

**`:action_confirmation` card**:
- Title + description from Claude's plan
- Mini data table showing target row(s) for verification
- Dynamic `confirm_message/1` text from the action module
- "Confirm" button (primary/green) and "Cancel" button (ghost)

**`:action_result` card**:
- Success: green card with check icon, summary message
- Error: red card with error message (no auto-retry for mutations)

### 8. DashboardLive Event Flow

```
User: "approve UPS org"
  → Task.async runs pipeline
  → Pipeline returns :action_confirmation result
  → Card rendered in grid with target details

User clicks "Confirm"
  → handle_event("confirm_action", %{"result_id" => id})
  → Retrieve pending action from socket assigns (pending_actions map)
  → ActionExecutor.execute_all(action_module, targets, params)
      → Calls action_module.execute/2 once per target row
      → Collects {:ok, _} / {:error, _} per target
  → Replace confirmation card with :action_result card

User clicks "Cancel"
  → handle_event("dismiss", ...) removes the card
```

**Multi-target execution**: `ActionExecutor.execute_all/3` iterates targets
sequentially, calling `execute/2` per row. The result card shows a summary:
- All succeeded: "Approved 3 organizations"
- Partial failure: "Approved 2 of 3 organizations (1 failed: reason)"
- All failed: error card with details

No rollback on partial failure — each `execute/2` call is independent.

**State**: DashboardLive stores `pending_actions: %{result_id => %Result{}}`
in assigns so the confirm handler can retrieve targets and action metadata.

### 9. New Modules Summary

| Module | Location | Purpose |
|--------|----------|---------|
| `Dai.Action` | `lib/dai/action.ex` | Behaviour definition |
| `Dai.AI.ActionRegistry` | `lib/dai/ai/action_registry.ex` | Reads config, lookup, prompt generation |
| `Dai.AI.ActionExecutor` | `lib/dai/ai/action_executor.ex` | Iterates targets, calls action module's execute/2 per row |

### 10. Modified Modules

| Module | Change |
|--------|--------|
| `Dai.Config` | Add `actions/0` accessor |
| `Dai.AI.SystemPrompt` | Append actions section when configured |
| `Dai.AI.PlanValidator` | Handle action plans (validate action_id + SELECT) |
| `Dai.AI.QueryPipeline` | Branch on plan type, build confirmation results |
| `Dai.AI.Result` | Add `:action_confirmation`, `:action_result` types and action fields |
| `Dai.DashboardLive` | Add `pending_actions` assign, confirm/cancel events |
| `Dai.DashboardComponents` | Add confirmation and result card components |

## Verification

1. **Unit test action modules**: `ApproveOrganization.execute(%{"id" => org.id}, %{})` with Ecto sandbox
2. **Unit test ActionRegistry**: verify `all/0`, `lookup/1`, `prompt_section/0` with test actions
3. **Unit test pipeline branching**: mock Client to return action plan, verify confirmation result
4. **LiveView test**: mount dashboard, submit action prompt, verify confirmation card renders, click confirm, verify result card
5. **Manual E2E**: In dev, type "approve the UPS organization" → see confirmation card with org details → click confirm → see success card → verify org is approved in DB

## Maildefender Actions (Initial Set)

| Action Module | id | Calls |
|---------------|-----|-------|
| `ApproveOrganization` | `approve_organization` | `Organizations.approve_organization/1` |
| `MarkLeadContacted` | `mark_lead_contacted` | `Organizations.mark_lead_contacted/1` |
| `SendNotification` | `send_notification` | `Organizations.create_notification/2` + Oban worker |
| `UpdateBrandContact` | `update_brand_contact` | `Organizations.update_brand/2` |
