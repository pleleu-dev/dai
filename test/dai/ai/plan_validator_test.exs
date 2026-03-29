defmodule Dai.AI.PlanValidatorTest do
  use ExUnit.Case, async: true

  alias Dai.AI.PlanValidator

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
  end
end
