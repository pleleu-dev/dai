defmodule Dai.AI.PlanValidatorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

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

  describe "LIMIT clamping (T1.1)" do
    test "clamps an over-large LIMIT down to the component default" do
      plan = %{@valid_plan | "sql" => "SELECT * FROM users LIMIT 5000000"}
      assert {:ok, validated} = PlanValidator.validate(plan)
      assert validated["sql"] == "SELECT * FROM users LIMIT 50"
    end

    test "clamps LIMIT ALL down to the component default" do
      plan = %{@valid_plan | "sql" => "SELECT * FROM users LIMIT ALL"}
      assert {:ok, validated} = PlanValidator.validate(plan)
      assert validated["sql"] == "SELECT * FROM users LIMIT 50"
    end

    test "clamps to the data_table default of 500" do
      plan = %{
        @valid_plan
        | "sql" => "SELECT * FROM users LIMIT 999999",
          "component" => "data_table"
      }

      assert {:ok, validated} = PlanValidator.validate(plan)
      assert validated["sql"] == "SELECT * FROM users LIMIT 500"
    end

    test "preserves a LIMIT already within the ceiling" do
      plan = %{@valid_plan | "sql" => "SELECT * FROM users LIMIT 10"}
      assert {:ok, validated} = PlanValidator.validate(plan)
      assert validated["sql"] == "SELECT * FROM users LIMIT 10"
    end

    test "appends the ceiling when no LIMIT is present" do
      plan = %{@valid_plan | "sql" => "SELECT * FROM users"}
      assert {:ok, validated} = PlanValidator.validate(plan)
      assert validated["sql"] == "SELECT * FROM users LIMIT 50"
    end

    test "honors the global max_rows ceiling when below the component default" do
      Application.put_env(:dai, :max_rows, 10)
      on_exit(fn -> Application.delete_env(:dai, :max_rows) end)

      plan = %{@valid_plan | "sql" => "SELECT * FROM users", "component" => "data_table"}
      assert {:ok, validated} = PlanValidator.validate(plan)
      assert validated["sql"] == "SELECT * FROM users LIMIT 10"
    end
  end

  describe "injection attempts (T1.4)" do
    test "rejects a stacked statement carrying a write" do
      plan = %{@valid_plan | "sql" => "SELECT 1; DELETE FROM users"}
      assert {:error, :forbidden_sql} = PlanValidator.validate(plan)
    end

    test "rejects a comment-bypass attempt that smuggles a write keyword" do
      plan = %{@valid_plan | "sql" => "SELECT 1 -- harmless\nDROP TABLE users"}
      assert {:error, :forbidden_sql} = PlanValidator.validate(plan)
    end

    test "rejects EXEC / CREATE / COPY keywords" do
      for keyword <- ["EXEC sp_who", "CREATE TABLE evil (x int)", "COPY users TO '/tmp/x'"] do
        plan = %{@valid_plan | "sql" => "SELECT 1; #{keyword}"}
        assert {:error, :forbidden_sql} = PlanValidator.validate(plan)
      end
    end

    # `pg_read_file` and other pg_-prefixed functions are deliberately NOT caught
    # by the keyword blocklist (see @moduledoc). They are contained by the
    # read-only execution boundary / GRANT SELECT role, exercised in
    # Dai.AI.SqlExecutorTest, not here.
  end

  describe "scope enforcement (T2.1)" do
    @scope %{column: "org_name", table: "users", value: "Acme"}

    test "blocks SQL missing the scope column and logs the offending SQL" do
      plan = %{@valid_plan | "sql" => "SELECT COUNT(*) FROM users LIMIT 50"}

      log =
        capture_log(fn ->
          assert {:error, :scope_violation} = PlanValidator.validate(plan, @scope)
        end)

      assert log =~ "not scoped to tenant"
    end

    test "passes SQL that references the scope column" do
      plan = %{
        @valid_plan
        | "sql" => "SELECT COUNT(*) FROM users WHERE org_name = 'Acme' LIMIT 50"
      }

      assert {:ok, _validated} = PlanValidator.validate(plan, @scope)
    end

    test "is unaffected when no scope is active" do
      plan = %{@valid_plan | "sql" => "SELECT COUNT(*) FROM users LIMIT 50"}
      assert {:ok, _validated} = PlanValidator.validate(plan, nil)
    end

    test "blocks action plans that are not scoped" do
      Application.put_env(:dai, :actions, [TestAction])
      on_exit(fn -> Application.delete_env(:dai, :actions) end)

      plan = %{
        "type" => "action",
        "title" => "Approve",
        "description" => "Approve",
        "sql" => "SELECT id, name FROM users WHERE id = 1",
        "action_id" => "test_action",
        "params" => %{}
      }

      assert capture_log(fn ->
               assert {:error, :scope_violation} = PlanValidator.validate(plan, @scope)
             end) =~ "not scoped to tenant"
    end
  end
end
