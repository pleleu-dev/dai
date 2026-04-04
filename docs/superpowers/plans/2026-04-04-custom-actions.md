# Dai Custom Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a generic action system to the Dai library so host apps can register custom actions (e.g., "approve organization") that Claude can propose and users can confirm within the dashboard.

**Architecture:** New `Dai.Action` behaviour defines action callbacks. Host apps register action modules via config. `ActionRegistry` reads config, provides lookup and prompt generation. `QueryPipeline` branches on `"type" => "action"` plans — validates, runs SELECT to find targets, builds confirmation result. `DashboardLive` stores pending actions and handles confirm/cancel events. `ActionExecutor` iterates targets and calls `execute/2` per row.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, daisyUI 5

---

## File Structure

| Action | File | Responsibility |
|---|---|---|
| Create | `lib/dai/action.ex` | Behaviour: `id/0`, `label/0`, `description/0`, `target_table/0`, `target_key/0`, `confirm_message/1`, `execute/2` |
| Create | `lib/dai/ai/action_registry.ex` | Reads config, `all/0`, `lookup/1`, `prompt_section/0` |
| Create | `lib/dai/ai/action_executor.ex` | `execute_all/3`: iterates targets, calls `execute/2` per row |
| Modify | `lib/dai/config.ex:45` | Add `actions/0` accessor |
| Modify | `lib/dai/ai/system_prompt.ex:4-57` | Append actions section when configured |
| Modify | `lib/dai/ai/plan_validator.ex:8-15` | Add action plan validation head |
| Modify | `lib/dai/ai/result.ex:4-36` | Add `:action_confirmation`, `:action_result` types + action fields |
| Modify | `lib/dai/ai/query_pipeline.ex:12-21` | Add action plan branching in `run_from_plan/2` |
| Modify | `lib/dai/dashboard_live.ex:164-188,204-206` | Add `pending_actions` assign, `confirm_action` event |
| Modify | `lib/dai/dashboard_components.ex:53-82` | Add confirmation + result card renderers |
| Create | `test/dai/ai/action_registry_test.exs` | Unit tests for registry |
| Create | `test/dai/ai/action_executor_test.exs` | Unit tests for executor |
| Create | `test/dai/ai/query_pipeline_action_test.exs` | Pipeline branching tests for action plans |

---

### Task 1: `Dai.Action` behaviour + `Dai.Config.actions/0`

**Files:**
- Create: `lib/dai/action.ex`
- Modify: `lib/dai/config.ex`

These are pure definitions with no logic to test — behaviour callbacks and a config accessor.

- [ ] **Step 1: Create the behaviour module**

```elixir
# lib/dai/action.ex
defmodule Dai.Action do
  @moduledoc "Behaviour for custom actions that can be executed from the Dai dashboard."

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

- [ ] **Step 2: Add `actions/0` to Config**

Add after the `max_tokens/0` function at the bottom of `lib/dai/config.ex`:

```elixir
  @spec actions() :: [module()]
  def actions do
    Application.get_env(:dai, :actions, [])
  end
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: compiles cleanly

- [ ] **Step 4: Commit**

```bash
git add lib/dai/action.ex lib/dai/config.ex
git commit -m "feat(actions): add Dai.Action behaviour and Config.actions/0"
```

---

### Task 2: `Dai.AI.ActionRegistry`

**Files:**
- Create: `test/dai/ai/action_registry_test.exs`
- Create: `lib/dai/ai/action_registry.ex`

- [ ] **Step 1: Create a test helper action module and write failing tests**

```elixir
# test/dai/ai/action_registry_test.exs
defmodule Dai.AI.ActionRegistryTest do
  use ExUnit.Case, async: true

  alias Dai.AI.ActionRegistry

  defmodule TestAction do
    @behaviour Dai.Action

    def id, do: "test_action"
    def label, do: "Test Action"
    def description, do: "A test action for unit tests"
    def target_table, do: "users"
    def target_key, do: "id"
    def confirm_message(target), do: "Run test on #{target["name"]}?"
    def execute(_target, _params), do: {:ok, :done}
  end

  defmodule AnotherAction do
    @behaviour Dai.Action

    def id, do: "another_action"
    def label, do: "Another Action"
    def description, do: "Another test action"
    def target_table, do: "plans"
    def target_key, do: "id"
    def confirm_message(_target), do: "Run another action?"
    def execute(_target, _params), do: {:ok, :done}
  end

  setup do
    prev = Application.get_env(:dai, :actions)
    Application.put_env(:dai, :actions, [TestAction, AnotherAction])
    on_exit(fn ->
      if prev, do: Application.put_env(:dai, :actions, prev), else: Application.delete_env(:dai, :actions)
    end)
  end

  describe "all/0" do
    test "returns metadata for all configured actions" do
      actions = ActionRegistry.all()
      assert length(actions) == 2
      assert %{id: "test_action", label: "Test Action", module: TestAction} = hd(actions)
    end

    test "returns empty list when no actions configured" do
      Application.put_env(:dai, :actions, [])
      assert ActionRegistry.all() == []
    end
  end

  describe "lookup/1" do
    test "finds action by string id" do
      assert {:ok, TestAction} = ActionRegistry.lookup("test_action")
    end

    test "returns :error for unknown id" do
      assert :error = ActionRegistry.lookup("nonexistent")
    end
  end

  describe "prompt_section/0" do
    test "generates prompt text listing all actions" do
      section = ActionRegistry.prompt_section()
      assert section =~ "test_action"
      assert section =~ "Test Action"
      assert section =~ "users"
      assert section =~ "action_id"
    end

    test "returns empty string when no actions configured" do
      Application.put_env(:dai, :actions, [])
      assert ActionRegistry.prompt_section() == ""
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/dai/ai/action_registry_test.exs`
Expected: FAIL — `ActionRegistry` module not found

- [ ] **Step 3: Implement ActionRegistry**

```elixir
# lib/dai/ai/action_registry.ex
defmodule Dai.AI.ActionRegistry do
  @moduledoc "Reads configured action modules and provides lookup and prompt generation."

  @spec all() :: [map()]
  def all do
    Enum.map(Dai.Config.actions(), fn module ->
      %{
        id: module.id(),
        label: module.label(),
        description: module.description(),
        target_table: module.target_table(),
        target_key: module.target_key(),
        module: module
      }
    end)
  end

  @spec lookup(String.t()) :: {:ok, module()} | :error
  def lookup(action_id) do
    case Enum.find(Dai.Config.actions(), fn mod -> mod.id() == action_id end) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  @spec prompt_section() :: String.t()
  def prompt_section do
    actions = all()

    if actions == [] do
      ""
    else
      action_lines =
        Enum.map_join(actions, "\n", fn a ->
          "- #{a.id}: #{a.label}. #{a.description}. Target: #{a.target_table} (key: #{a.target_key})"
        end)

      """
      ## Available Actions

      When the user asks you to perform an action (not just view data), return an action plan instead of a query plan.

      Actions:
      #{action_lines}

      Action response format:
      {"type": "action", "title": "...", "description": "...", "sql": "SELECT ... FROM {target_table} WHERE ...", "action_id": "{id}", "params": {}}

      The SQL must be a SELECT that finds the target row(s). Include enough columns for the user to verify the targets.
      """
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/dai/ai/action_registry_test.exs`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/dai/ai/action_registry.ex test/dai/ai/action_registry_test.exs
git commit -m "feat(actions): add ActionRegistry with lookup and prompt generation"
```

---

### Task 3: Extend `Dai.AI.Result` with action types and fields

**Files:**
- Modify: `lib/dai/ai/result.ex`

- [ ] **Step 1: Add action types and fields to the Result struct**

In `lib/dai/ai/result.ex`, update the type spec (lines 4-22) to add `:action_confirmation` and `:action_result`:

```elixir
  @type t :: %__MODULE__{
          id: String.t(),
          type:
            :kpi_metric
            | :bar_chart
            | :line_chart
            | :pie_chart
            | :data_table
            | :clarification
            | :error
            | :action_confirmation
            | :action_result,
          title: String.t() | nil,
          description: String.t() | nil,
          config: map() | nil,
          data: %{columns: [String.t()], rows: [map()]} | nil,
          prompt: String.t(),
          error: String.t() | nil,
          question: String.t() | nil,
          action_id: String.t() | nil,
          action_targets: [map()] | nil,
          action_params: map() | nil,
          timestamp: DateTime.t()
        }
```

Add the new fields to the `defstruct` list (after `:question`):

```elixir
  defstruct [
    :id,
    :type,
    :title,
    :description,
    :config,
    :data,
    :prompt,
    :error,
    :question,
    :action_id,
    :action_targets,
    :action_params,
    :timestamp
  ]
```

Add error message clauses for new error atoms (before the catch-all `error_message/1` clauses):

```elixir
  defp error_message(:invalid_action), do: "The AI suggested an unknown action."
```

- [ ] **Step 2: Verify existing tests still pass**

Run: `mix test test/dai/ai/`
Expected: all existing tests pass (struct changes are backward-compatible)

- [ ] **Step 3: Commit**

```bash
git add lib/dai/ai/result.ex
git commit -m "feat(actions): add action_confirmation/action_result types to Result"
```

---

### Task 4: Extend `Dai.AI.PlanValidator` for action plans

**Files:**
- Modify: `test/dai/ai/plan_validator_test.exs`
- Modify: `lib/dai/ai/plan_validator.ex`

- [ ] **Step 1: Write failing tests for action plan validation**

Add to `test/dai/ai/plan_validator_test.exs`, inside the existing `describe "validate/1"` block:

```elixir
    test "accepts a valid action plan" do
      Application.put_env(:dai, :actions, [Dai.AI.PlanValidatorTest.TestAction])
      on_exit(fn -> Application.delete_env(:dai, :actions) end)

      plan = %{
        "type" => "action",
        "title" => "Approve Org",
        "description" => "Approve the org",
        "sql" => "SELECT id, name FROM users WHERE id = 1",
        "action_id" => "test_action",
        "params" => %{}
      }

      assert {:ok, ^plan} = PlanValidator.validate(plan)
    end

    test "rejects action plan with unknown action_id" do
      Application.put_env(:dai, :actions, [])
      on_exit(fn -> Application.delete_env(:dai, :actions) end)

      plan = %{
        "type" => "action",
        "title" => "Bad",
        "description" => "Bad action",
        "sql" => "SELECT id FROM users",
        "action_id" => "nonexistent",
        "params" => %{}
      }

      assert {:error, :invalid_action} = PlanValidator.validate(plan)
    end

    test "rejects action plan with forbidden SQL" do
      Application.put_env(:dai, :actions, [Dai.AI.PlanValidatorTest.TestAction])
      on_exit(fn -> Application.delete_env(:dai, :actions) end)

      plan = %{
        "type" => "action",
        "title" => "Bad",
        "description" => "Bad",
        "sql" => "DELETE FROM users",
        "action_id" => "test_action",
        "params" => %{}
      }

      assert {:error, :forbidden_sql} = PlanValidator.validate(plan)
    end

    test "does not enforce LIMIT on action plans" do
      Application.put_env(:dai, :actions, [Dai.AI.PlanValidatorTest.TestAction])
      on_exit(fn -> Application.delete_env(:dai, :actions) end)

      plan = %{
        "type" => "action",
        "title" => "Approve",
        "description" => "Approve",
        "sql" => "SELECT id, name FROM users WHERE active = true",
        "action_id" => "test_action",
        "params" => %{}
      }

      assert {:ok, validated} = PlanValidator.validate(plan)
      refute String.contains?(validated["sql"], "LIMIT")
    end
```

Also add a test helper module at the top of the test file, inside the module but before `describe`:

```elixir
  defmodule TestAction do
    @behaviour Dai.Action

    def id, do: "test_action"
    def label, do: "Test Action"
    def description, do: "Test action"
    def target_table, do: "users"
    def target_key, do: "id"
    def confirm_message(_target), do: "Run test?"
    def execute(_target, _params), do: {:ok, :done}
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/dai/ai/plan_validator_test.exs`
Expected: FAIL — new tests fail (action plans currently match `validate(_plan)` catch-all)

- [ ] **Step 3: Add action plan validation head to PlanValidator**

In `lib/dai/ai/plan_validator.ex`, add a new `validate/1` clause **before** the existing `validate(%{"sql" => sql, "component" => component})` clause (before line 8):

```elixir
  alias Dai.AI.ActionRegistry

  def validate(%{"type" => "action", "sql" => sql, "action_id" => action_id} = plan) do
    with :ok <- check_forbidden_keywords(sql),
         :ok <- check_action(action_id) do
      {:ok, plan}
    end
  end
```

Add a new private function (after `check_component/1`):

```elixir
  defp check_action(action_id) do
    case ActionRegistry.lookup(action_id) do
      {:ok, _module} -> :ok
      :error -> {:error, :invalid_action}
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/dai/ai/plan_validator_test.exs`
Expected: all pass (old + new)

- [ ] **Step 5: Commit**

```bash
git add lib/dai/ai/plan_validator.ex test/dai/ai/plan_validator_test.exs
git commit -m "feat(actions): validate action plans in PlanValidator"
```

---

### Task 5: Extend `Dai.AI.SystemPrompt` to include actions

**Files:**
- Modify: `lib/dai/ai/system_prompt.ex`

- [ ] **Step 1: Append actions section conditionally**

Replace the `build/1` function in `lib/dai/ai/system_prompt.ex` with:

```elixir
  alias Dai.AI.ActionRegistry

  def build(schema_context) do
    base_prompt = """
    You are a SQL query generator for a PostgreSQL database. You must respond with ONLY a valid JSON object. No markdown fences, no explanation, no text before or after the JSON. Read-only SELECT queries only.

    ## Database Schema

    #{schema_context}

    ## Rules

    1. Choose the best visualization component based on the data shape:
       - Single scalar value (COUNT, SUM, AVG, single row/column) → "kpi_metric"
       - Time series (date/datetime column + numeric column, ordered by date) → "line_chart"
       - Categorical comparison (label column + numeric column, grouped) → "bar_chart"
       - Part-of-whole proportions (< 8 categories with a numeric value) → "pie_chart"
       - Multiple columns or raw row data → "data_table"

    2. All queries must be read-only SELECT statements. Never generate INSERT, UPDATE, DELETE, DROP, or any DDL/DML.

    3. Always include a LIMIT clause: LIMIT 50 for charts and KPIs, LIMIT 500 for data tables.

    4. If the user's question is ambiguous and you cannot determine the intent, return a clarification request instead of SQL.

    ## Response Format

    For a query, return exactly:
    ```
    {"title": "Human-readable title", "description": "One-line explanation", "sql": "SELECT ...", "component": "kpi_metric|bar_chart|line_chart|pie_chart|data_table", "config": {...}}
    ```

    Config varies by component:
    - kpi_metric: {"label": "Label", "format": "number|currency|percent"}
    - bar_chart: {"x_axis": "column_name", "y_axis": "column_name", "orientation": "vertical|horizontal"}
    - line_chart: {"x_axis": "column_name", "y_axis": "column_name", "fill": true|false}
    - pie_chart: {"label_field": "column_name", "value_field": "column_name"}
    - data_table: {"columns": ["col1", "col2"]}

    For a clarification, return exactly:
    ```
    {"needs_clarification": true, "question": "Your follow-up question"}
    ```

    ## Examples

    User: "how many active subscribers do we have?"
    {"title": "Active Subscribers", "description": "Count of subscriptions with active status", "sql": "SELECT COUNT(*) AS count FROM subscriptions WHERE status = 'active' LIMIT 50", "component": "kpi_metric", "config": {"label": "Active Subscribers", "format": "number"}}

    User: "show revenue by plan this month"
    {"title": "Revenue by Plan This Month", "description": "Total invoice amount grouped by plan name for the current month", "sql": "SELECT p.name AS plan_name, SUM(i.amount_cents) / 100.0 AS revenue FROM invoices i JOIN subscriptions s ON s.id = i.subscription_id JOIN plans p ON p.id = s.plan_id WHERE i.due_date >= date_trunc('month', CURRENT_DATE) AND i.status = 'paid' GROUP BY p.name ORDER BY revenue DESC LIMIT 50", "component": "bar_chart", "config": {"x_axis": "plan_name", "y_axis": "revenue", "orientation": "vertical"}}

    User: "show me recent failed invoices"
    {"title": "Recent Failed Invoices", "description": "Most recent invoices with failed status", "sql": "SELECT i.id, i.amount_cents / 100.0 AS amount, i.due_date, i.status, p.name AS plan_name FROM invoices i JOIN subscriptions s ON s.id = i.subscription_id JOIN plans p ON p.id = s.plan_id WHERE i.status = 'failed' ORDER BY i.due_date DESC LIMIT 500", "component": "data_table", "config": {"columns": ["id", "amount", "due_date", "status", "plan_name"]}}
    """

    actions_section = ActionRegistry.prompt_section()

    if actions_section == "" do
      base_prompt
    else
      base_prompt <> "\n" <> actions_section
    end
  end
```

- [ ] **Step 2: Verify compilation and existing tests pass**

Run: `mix test`
Expected: all pass

- [ ] **Step 3: Commit**

```bash
git add lib/dai/ai/system_prompt.ex
git commit -m "feat(actions): extend system prompt with available actions section"
```

---

### Task 6: `Dai.AI.ActionExecutor`

**Files:**
- Create: `test/dai/ai/action_executor_test.exs`
- Create: `lib/dai/ai/action_executor.ex`

- [ ] **Step 1: Write failing tests**

```elixir
# test/dai/ai/action_executor_test.exs
defmodule Dai.AI.ActionExecutorTest do
  use ExUnit.Case, async: true

  alias Dai.AI.ActionExecutor

  defmodule SuccessAction do
    @behaviour Dai.Action

    def id, do: "success"
    def label, do: "Success"
    def description, do: "Always succeeds"
    def target_table, do: "users"
    def target_key, do: "id"
    def confirm_message(target), do: "Act on #{target["name"]}?"

    def execute(target, _params) do
      {:ok, %{id: target["id"]}}
    end
  end

  defmodule FailAction do
    @behaviour Dai.Action

    def id, do: "fail"
    def label, do: "Fail"
    def description, do: "Always fails"
    def target_table, do: "users"
    def target_key, do: "id"
    def confirm_message(_target), do: "Act?"

    def execute(_target, _params) do
      {:error, "something went wrong"}
    end
  end

  describe "execute_all/3" do
    test "executes action on each target and returns all successes" do
      targets = [%{"id" => 1, "name" => "A"}, %{"id" => 2, "name" => "B"}]

      assert {:ok, results} = ActionExecutor.execute_all(SuccessAction, targets, %{})
      assert length(results) == 2
    end

    test "returns partial failure with details" do
      # Use a module that fails on specific targets
      targets = [%{"id" => 1, "name" => "A"}]

      assert {:error, "something went wrong"} =
               ActionExecutor.execute_all(FailAction, targets, %{})
    end

    test "handles mixed success and failure" do
      # SuccessAction always succeeds — test single target for simplicity
      targets = [%{"id" => 1, "name" => "A"}]
      assert {:ok, _} = ActionExecutor.execute_all(SuccessAction, targets, %{})
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/dai/ai/action_executor_test.exs`
Expected: FAIL — `ActionExecutor` module not found

- [ ] **Step 3: Implement ActionExecutor**

```elixir
# lib/dai/ai/action_executor.ex
defmodule Dai.AI.ActionExecutor do
  @moduledoc "Executes an action against one or more target rows."

  @spec execute_all(module(), [map()], map()) ::
          {:ok, [term()]} | {:partial, [term()], [{map(), term()}]} | {:error, term()}
  def execute_all(action_module, targets, params) do
    results =
      Enum.map(targets, fn target ->
        {target, action_module.execute(target, params)}
      end)

    successes = for {_t, {:ok, val}} <- results, do: val
    failures = for {t, {:error, reason}} <- results, do: {t, reason}

    case {successes, failures} do
      {_, []} -> {:ok, successes}
      {[], [{_t, reason} | _]} -> {:error, reason}
      {_, _} -> {:partial, successes, failures}
    end
  end
end
```

- [ ] **Step 4: Update test to cover partial failure**

Replace the "handles mixed success and failure" test and add a proper partial failure test:

```elixir
    test "returns partial result when some targets fail" do
      defmodule MixedAction do
        @behaviour Dai.Action

        def id, do: "mixed"
        def label, do: "Mixed"
        def description, do: "Fails on id 2"
        def target_table, do: "users"
        def target_key, do: "id"
        def confirm_message(_target), do: "Act?"

        def execute(%{"id" => 2}, _params), do: {:error, "failed on 2"}
        def execute(target, _params), do: {:ok, %{id: target["id"]}}
      end

      targets = [%{"id" => 1, "name" => "A"}, %{"id" => 2, "name" => "B"}]
      assert {:partial, [%{id: 1}], [{%{"id" => 2, "name" => "B"}, "failed on 2"}]} =
               ActionExecutor.execute_all(MixedAction, targets, %{})
    end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/dai/ai/action_executor_test.exs`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add lib/dai/ai/action_executor.ex test/dai/ai/action_executor_test.exs
git commit -m "feat(actions): add ActionExecutor with per-row execution and partial failure"
```

---

### Task 7: Extend `Dai.AI.QueryPipeline` for action plans

**Files:**
- Create: `test/dai/ai/query_pipeline_action_test.exs`
- Modify: `lib/dai/ai/query_pipeline.ex`

- [ ] **Step 1: Write failing tests for action plan branching**

```elixir
# test/dai/ai/query_pipeline_action_test.exs
defmodule Dai.AI.QueryPipelineActionTest do
  use Dai.DataCase, async: true

  alias Dai.AI.{QueryPipeline, Result}

  defmodule TestAction do
    @behaviour Dai.Action

    def id, do: "test_action"
    def label, do: "Test Action"
    def description, do: "Test"
    def target_table, do: "users"
    def target_key, do: "id"
    def confirm_message(target), do: "Act on #{target["name"]}?"
    def execute(_target, _params), do: {:ok, :done}
  end

  setup do
    prev = Application.get_env(:dai, :actions)
    Application.put_env(:dai, :actions, [TestAction])
    on_exit(fn ->
      if prev, do: Application.put_env(:dai, :actions, prev), else: Application.delete_env(:dai, :actions)
    end)
  end

  describe "run_from_plan/2 with action plans" do
    test "returns action_confirmation result with target rows" do
      plan = %{
        "type" => "action",
        "title" => "Test Users",
        "description" => "Run test on matching users",
        "sql" => "SELECT id, email FROM users LIMIT 5",
        "action_id" => "test_action",
        "params" => %{}
      }

      assert {:ok, %Result{} = result} = QueryPipeline.run_from_plan(plan, "test the users")
      assert result.type == :action_confirmation
      assert result.action_id == "test_action"
      assert result.title == "Test Users"
      assert is_list(result.action_targets)
      assert result.action_params == %{}
    end

    test "returns error for unknown action_id" do
      plan = %{
        "type" => "action",
        "title" => "Bad",
        "description" => "Bad",
        "sql" => "SELECT id FROM users",
        "action_id" => "nonexistent",
        "params" => %{}
      }

      assert {:error, :invalid_action} = QueryPipeline.run_from_plan(plan, "bad action")
    end

    test "returns error for forbidden SQL in action plan" do
      plan = %{
        "type" => "action",
        "title" => "Bad",
        "description" => "Bad",
        "sql" => "DELETE FROM users",
        "action_id" => "test_action",
        "params" => %{}
      }

      assert {:error, :forbidden_sql} = QueryPipeline.run_from_plan(plan, "bad sql")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/dai/ai/query_pipeline_action_test.exs`
Expected: FAIL — action plans fall through to existing `run_from_plan/2` which expects `"component"` key

- [ ] **Step 3: Add action plan clause to QueryPipeline**

In `lib/dai/ai/query_pipeline.ex`, add a new `run_from_plan/2` clause **between** the clarification clause (line 12) and the default clause (line 16):

```elixir
  def run_from_plan(%{"type" => "action"} = plan, prompt) do
    with {:ok, validated} <- PlanValidator.validate(plan),
         {:ok, query_result} <- SqlExecutor.execute(validated) do
      {:ok,
       %Result{
         id: Result.generate_id(),
         type: :action_confirmation,
         title: validated["title"],
         description: validated["description"],
         action_id: validated["action_id"],
         action_targets: query_result.rows,
         action_params: validated["params"] || %{},
         data: query_result,
         prompt: prompt,
         timestamp: DateTime.utc_now()
       }}
    end
  end
```

Also add `Result` to the alias list at line 4:

```elixir
  alias Dai.AI.{Client, PlanValidator, Result, SqlExecutor, ResultAssembler}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/dai/ai/query_pipeline_action_test.exs test/dai/ai/query_pipeline_test.exs`
Expected: all pass (old + new)

- [ ] **Step 5: Commit**

```bash
git add lib/dai/ai/query_pipeline.ex test/dai/ai/query_pipeline_action_test.exs
git commit -m "feat(actions): add action plan branching to QueryPipeline"
```

---

### Task 8: Confirmation and result card components

**Files:**
- Modify: `lib/dai/dashboard_components.ex`

- [ ] **Step 1: Add `card_body` clause for `:action_confirmation`**

In `lib/dai/dashboard_components.ex`, add after the `:clarification` clause (after line 82):

```elixir
  defp card_body(%{result: %{type: :action_confirmation}} = assigns) do
    ~H"""
    <.action_confirmation_card result={@result} />
    """
  end

  defp card_body(%{result: %{type: :action_result}} = assigns) do
    ~H"""
    <.action_result_card result={@result} />
    """
  end
```

- [ ] **Step 2: Add the action_confirmation_card component**

Add after the `clarification_card` component:

```elixir
  attr :result, Result, required: true

  defp action_confirmation_card(assigns) do
    action_module = Dai.AI.ActionRegistry.lookup!(assigns.result.action_id)
    targets = assigns.result.action_targets || []

    confirm_messages =
      Enum.map(targets, fn target -> action_module.confirm_message(target) end)

    columns = assigns.result.data && assigns.result.data.columns || []

    assigns =
      assign(assigns,
        targets: targets,
        columns: columns,
        confirm_messages: confirm_messages
      )

    ~H"""
    <div class="flex flex-col gap-3 py-2">
      <div class="overflow-x-auto max-h-48">
        <table class="table table-xs">
          <thead>
            <tr>
              <th :for={col <- @columns} class="text-base-content/70">{col}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @targets} class="hover:bg-base-200/50">
              <td :for={col <- @columns} class="text-sm">{format_cell(row[col])}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div :for={msg <- @confirm_messages} class="flex items-center gap-2 text-sm text-base-content/80">
        <Icons.exclamation_triangle class="size-4 text-warning shrink-0" />
        <span>{msg}</span>
      </div>
      <div class="flex gap-2 justify-end">
        <button
          phx-click="dismiss"
          phx-value-id={@result.id}
          class="btn btn-ghost btn-sm"
        >
          Cancel
        </button>
        <button
          phx-click="confirm_action"
          phx-value-result-id={@result.id}
          class="btn btn-primary btn-sm"
        >
          Confirm
        </button>
      </div>
    </div>
    """
  end
```

- [ ] **Step 3: Add the action_result_card component**

```elixir
  attr :result, Result, required: true

  defp action_result_card(assigns) do
    success = assigns.result.error == nil
    assigns = assign(assigns, success: success)

    ~H"""
    <div class={[
      "flex flex-col items-center gap-3 py-4",
      @success && "text-success",
      !@success && "text-error"
    ]}>
      <div class="flex items-center gap-2">
        <Icons.check :if={@success} class="size-5" />
        <Icons.exclamation_triangle :if={!@success} class="size-5" />
        <span class="text-sm">{@result.description}</span>
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Add `lookup!/1` to ActionRegistry**

The confirmation card needs `lookup!/1`. Add to `lib/dai/ai/action_registry.ex`:

```elixir
  @spec lookup!(String.t()) :: module()
  def lookup!(action_id) do
    case lookup(action_id) do
      {:ok, module} -> module
      :error -> raise ArgumentError, "Unknown action: #{action_id}"
    end
  end
```

- [ ] **Step 5: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: compiles cleanly

- [ ] **Step 6: Commit**

```bash
git add lib/dai/dashboard_components.ex lib/dai/ai/action_registry.ex
git commit -m "feat(actions): add confirmation and result card components"
```

---

### Task 9: DashboardLive event handlers for confirm/cancel

**Files:**
- Modify: `lib/dai/dashboard_live.ex`

- [ ] **Step 1: Add `pending_actions` to mount assigns**

In `lib/dai/dashboard_live.ex`, add `pending_actions: %{}` to the `assign` call in `mount/3` (after `current_prompt: nil` at line 173):

```elixir
       current_prompt: nil,
       pending_actions: %{},
       task_ref: nil,
```

- [ ] **Step 2: Store action confirmations in pending_actions**

Add `ActionExecutor` and `ActionRegistry` to the alias at line 4:

```elixir
  alias Dai.AI.{ActionExecutor, ActionRegistry, QueryPipeline, Result}
```

Modify the single query result handler (line 405-411). Replace:

```elixir
  def handle_info({ref, result}, socket) when socket.assigns.task_ref == ref do
    Process.demonitor(ref, [:flush])

    {:noreply,
     socket
     |> stream_insert(:results, result_to_card(result, socket.assigns.current_prompt), at: 0)
     |> assign(loading: false, task_ref: nil)}
  end
```

With:

```elixir
  def handle_info({ref, result}, socket) when socket.assigns.task_ref == ref do
    Process.demonitor(ref, [:flush])
    card = result_to_card(result, socket.assigns.current_prompt)

    socket =
      socket
      |> stream_insert(:results, card, at: 0)
      |> assign(loading: false, task_ref: nil)
      |> maybe_store_pending_action(card)

    {:noreply, socket}
  end
```

Add a private helper:

```elixir
  defp maybe_store_pending_action(socket, %Result{type: :action_confirmation} = result) do
    assign(socket,
      pending_actions: Map.put(socket.assigns.pending_actions, result.id, result)
    )
  end

  defp maybe_store_pending_action(socket, _result), do: socket
```

- [ ] **Step 3: Add the confirm_action event handler**

Add after the `"dismiss"` handler (after line 206):

```elixir
  def handle_event("confirm_action", %{"result-id" => result_id}, socket) do
    case Map.pop(socket.assigns.pending_actions, result_id) do
      {nil, _} ->
        {:noreply, socket}

      {pending_result, remaining} ->
        {:ok, action_module} = ActionRegistry.lookup(pending_result.action_id)

        outcome =
          ActionExecutor.execute_all(
            action_module,
            pending_result.action_targets,
            pending_result.action_params
          )

        result_card = build_action_result(outcome, pending_result, action_module)

        {:noreply,
         socket
         |> stream_delete_by_dom_id(:results, "results-#{result_id}")
         |> stream_insert(:results, result_card, at: 0)
         |> assign(pending_actions: remaining)}
    end
  end
```

Add the private helper to build action result cards:

```elixir
  defp build_action_result({:ok, successes}, pending, action_module) do
    count = length(successes)

    %Result{
      id: Result.generate_id(),
      type: :action_result,
      title: action_module.label(),
      description: "Successfully completed #{action_module.label()} on #{count} #{if count == 1, do: "target", else: "targets"}.",
      prompt: pending.prompt,
      timestamp: DateTime.utc_now()
    }
  end

  defp build_action_result({:partial, successes, failures}, pending, action_module) do
    total = length(successes) + length(failures)
    failed = length(failures)
    {_target, first_reason} = hd(failures)

    %Result{
      id: Result.generate_id(),
      type: :action_result,
      title: action_module.label(),
      description: "Completed #{length(successes)} of #{total}. #{failed} failed: #{first_reason}",
      error: "#{failed} of #{total} failed",
      prompt: pending.prompt,
      timestamp: DateTime.utc_now()
    }
  end

  defp build_action_result({:error, reason}, pending, action_module) do
    %Result{
      id: Result.generate_id(),
      type: :action_result,
      title: action_module.label(),
      description: "Failed: #{reason}",
      error: to_string(reason),
      prompt: pending.prompt,
      timestamp: DateTime.utc_now()
    }
  end
```

- [ ] **Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: compiles cleanly

- [ ] **Step 5: Commit**

```bash
git add lib/dai/dashboard_live.ex
git commit -m "feat(actions): add pending_actions and confirm_action event to DashboardLive"
```

---

### Task 10: Update result_card to hide save button for action types

**Files:**
- Modify: `lib/dai/dashboard_components.ex`

- [ ] **Step 1: Update the save button guard**

In `lib/dai/dashboard_components.ex`, line 29, update the `:if` condition to also hide save for action types:

Replace:
```elixir
              :if={@result.type not in [:error, :clarification]}
```

With:
```elixir
              :if={@result.type not in [:error, :clarification, :action_confirmation, :action_result]}
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: compiles cleanly

- [ ] **Step 3: Commit**

```bash
git add lib/dai/dashboard_components.ex
git commit -m "fix(actions): hide save button on action confirmation and result cards"
```

---

### Task 11: Full integration — `mix precommit`

- [ ] **Step 1: Run the full precommit suite**

Run: `mix precommit`
Expected: all checks pass (compile warnings, unused deps, format, tests)

- [ ] **Step 2: Fix any issues found**

Address any compilation warnings, formatting issues, or test failures.

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "chore(actions): fix precommit issues"
```
