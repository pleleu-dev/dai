defmodule Dai.AI.PlanValidatorTest do
  use ExUnit.Case, async: true

  alias Dai.AI.PlanValidator

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

  @valid_plan %{
    "title" => "Test",
    "description" => "Test query",
    "sql" => "SELECT COUNT(*) FROM users LIMIT 50",
    "component" => "kpi_metric",
    "config" => %{"label" => "Users", "format" => "number"}
  }

  describe "validate/1" do
    test "accepts a valid plan" do
      assert {:ok, plan} = PlanValidator.validate(@valid_plan)
      assert plan["sql"] == "SELECT COUNT(*) FROM users LIMIT 50"
    end

    test "rejects forbidden SQL keywords" do
      for keyword <- ["INSERT", "UPDATE", "DELETE", "DROP", "TRUNCATE", "ALTER"] do
        plan = %{@valid_plan | "sql" => "#{keyword} INTO users VALUES (1)"}
        assert {:error, :forbidden_sql} = PlanValidator.validate(plan)
      end
    end

    test "rejects forbidden keywords case-insensitively" do
      plan = %{@valid_plan | "sql" => "delete from users"}
      assert {:error, :forbidden_sql} = PlanValidator.validate(plan)
    end

    test "rejects invalid component type" do
      plan = %{@valid_plan | "component" => "sparkline"}
      assert {:error, :invalid_component} = PlanValidator.validate(plan)
    end

    test "appends LIMIT 50 for chart components when missing" do
      plan = %{
        @valid_plan
        | "sql" => "SELECT name, COUNT(*) FROM users GROUP BY name",
          "component" => "bar_chart"
      }

      assert {:ok, validated} = PlanValidator.validate(plan)
      assert String.ends_with?(validated["sql"], " LIMIT 50")
    end

    test "appends LIMIT 500 for data_table when missing" do
      plan = %{@valid_plan | "sql" => "SELECT * FROM users", "component" => "data_table"}
      assert {:ok, validated} = PlanValidator.validate(plan)
      assert String.ends_with?(validated["sql"], " LIMIT 500")
    end

    test "does not double-add LIMIT when already present" do
      plan = %{@valid_plan | "sql" => "SELECT * FROM users LIMIT 10"}
      assert {:ok, validated} = PlanValidator.validate(plan)
      assert validated["sql"] == "SELECT * FROM users LIMIT 10"
    end

    test "rejects plan with missing sql key" do
      plan = Map.delete(@valid_plan, "sql")
      assert {:error, :invalid_plan} = PlanValidator.validate(plan)
    end

    test "accepts a valid action plan" do
      Application.put_env(:dai, :actions, [TestAction])
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
      Application.put_env(:dai, :actions, [TestAction])
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
      Application.put_env(:dai, :actions, [TestAction])
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
  end
end
