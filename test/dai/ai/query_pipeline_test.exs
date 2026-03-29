defmodule Dai.AI.QueryPipelineTest do
  use Dai.DataCase, async: true

  alias Dai.AI.{QueryPipeline, Result}

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
end
