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
      if prev,
        do: Application.put_env(:dai, :actions, prev),
        else: Application.delete_env(:dai, :actions)
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
