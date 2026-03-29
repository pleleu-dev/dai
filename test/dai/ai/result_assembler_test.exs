defmodule Dai.AI.ResultAssemblerTest do
  use ExUnit.Case, async: true

  alias Dai.AI.{Result, ResultAssembler}

  @plan %{
    "title" => "Active Users",
    "description" => "Count of active users",
    "sql" => "SELECT COUNT(*) AS count FROM users",
    "component" => "kpi_metric",
    "config" => %{"label" => "Active Users", "format" => "number"}
  }

  @query_result %{columns: ["count"], rows: [%{"count" => 42}]}

  describe "assemble/3" do
    test "builds a Result struct from plan and query result" do
      assert {:ok, %Result{} = result} =
               ResultAssembler.assemble(@plan, @query_result, "how many users?")

      assert result.type == :kpi_metric
      assert result.title == "Active Users"
      assert result.description == "Count of active users"
      assert result.data == @query_result
      assert result.config == %{"label" => "Active Users", "format" => "number"}
      assert result.prompt == "how many users?"
      assert is_binary(result.id)
      assert String.length(result.id) == 8
    end

    test "builds a clarification result" do
      plan = %{"needs_clarification" => true, "question" => "Which time range?"}

      assert {:ok, %Result{} = result} =
               ResultAssembler.assemble_clarification(plan, "show revenue")

      assert result.type == :clarification
      assert result.question == "Which time range?"
    end

    test "maps all component types to atoms" do
      for {str, atom} <- [
            {"kpi_metric", :kpi_metric},
            {"bar_chart", :bar_chart},
            {"line_chart", :line_chart},
            {"pie_chart", :pie_chart},
            {"data_table", :data_table}
          ] do
        plan = %{@plan | "component" => str}
        {:ok, result} = ResultAssembler.assemble(plan, @query_result, "test")
        assert result.type == atom
      end
    end
  end
end
