defmodule Dai.AI.QueryPipelineTest do
  use Dai.DataCase, async: true

  import ExUnit.CaptureLog
  import Mox

  alias Dai.AI.{ClientMock, QueryPipeline, Result}

  setup :verify_on_exit!

  describe "run_from_plan/2" do
    test "returns a Result for a valid plan" do
      plan = %{
        "title" => "User Count",
        "description" => "Total number of users",
        "sql" => "SELECT COUNT(*) AS count FROM users",
        "component" => "kpi_metric",
        "config" => %{"label" => "Users", "format" => "number"}
      }

      assert {:ok, %Result{} = result} = QueryPipeline.run_from_plan(plan, "how many users?")
      assert result.type == :kpi_metric
      assert result.title == "User Count"
      assert is_list(result.data.rows)
    end

    test "returns error for forbidden SQL" do
      plan = %{
        "title" => "Bad",
        "description" => "Bad query",
        "sql" => "DELETE FROM users",
        "component" => "data_table",
        "config" => %{"columns" => ["id"]}
      }

      assert {:error, :forbidden_sql} = QueryPipeline.run_from_plan(plan, "delete users")
    end

    test "handles clarification plans" do
      plan = %{"needs_clarification" => true, "question" => "Which time period?"}

      assert {:ok, %Result{type: :clarification, question: "Which time period?"}} =
               QueryPipeline.run_from_plan(plan, "show revenue")
    end
  end

  describe "run_from_plan/3 with tenant scope (T2.4)" do
    @scope %{column: "org_name", table: "users", value: "Acme"}

    test "blocks an unscoped plan before it reaches the database" do
      plan = %{
        "title" => "All Users",
        "description" => "Count of every user",
        "sql" => "SELECT COUNT(*) AS count FROM users",
        "component" => "kpi_metric",
        "config" => %{"label" => "Users", "format" => "number"}
      }

      capture_log(fn ->
        assert {:error, :scope_violation} =
                 QueryPipeline.run_from_plan(plan, "how many users?", @scope)
      end)
    end

    test "executes a plan that references the scope column" do
      plan = %{
        "title" => "Acme Users",
        "description" => "Count of users in the org",
        "sql" => "SELECT COUNT(*) AS count FROM users WHERE org_name = 'Acme'",
        "component" => "kpi_metric",
        "config" => %{"label" => "Users", "format" => "number"}
      }

      assert {:ok, %Result{type: :kpi_metric} = result} =
               QueryPipeline.run_from_plan(plan, "how many Acme users?", @scope)

      assert is_list(result.data.rows)
    end
  end

  describe "run/3 end-to-end with a stubbed client (T6.1)" do
    test "drives a returned plan through validation, execution, and assembly" do
      plan = %{
        "title" => "User Count",
        "description" => "Total number of users",
        "sql" => "SELECT COUNT(*) AS count FROM users",
        "component" => "kpi_metric",
        "config" => %{"label" => "Users", "format" => "number"}
      }

      expect(ClientMock, :generate_plan, fn "how many users?", _schema, opts ->
        assert Keyword.fetch!(opts, :scope) == nil
        {:ok, plan}
      end)

      assert {:ok, %Result{type: :kpi_metric, title: "User Count"} = result} =
               QueryPipeline.run("how many users?", "schema-context", client: ClientMock)

      assert is_list(result.data.rows)
    end

    test "propagates a client error without running SQL" do
      expect(ClientMock, :generate_plan, fn _prompt, _schema, _opts -> {:error, :api_error} end)

      assert {:error, :api_error} =
               QueryPipeline.run("anything", "schema-context", client: ClientMock)
    end

    test "handles a clarification plan from the client" do
      expect(ClientMock, :generate_plan, fn _prompt, _schema, _opts ->
        {:ok, %{"needs_clarification" => true, "question" => "Which period?"}}
      end)

      assert {:ok, %Result{type: :clarification, question: "Which period?"}} =
               QueryPipeline.run("revenue", "schema-context", client: ClientMock)
    end
  end
end
