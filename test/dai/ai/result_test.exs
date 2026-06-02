defmodule Dai.AI.ResultTest do
  use ExUnit.Case, async: true

  alias Dai.AI.Result

  describe "layout_key field" do
    test "result struct includes layout_key field" do
      result = %Result{
        id: "abc",
        type: :kpi_metric,
        prompt: "show MRR",
        timestamp: DateTime.utc_now(),
        layout_key: "test123"
      }

      assert result.layout_key == "test123"
    end

    test "layout_key defaults to nil" do
      result = %Result{
        id: "abc",
        type: :kpi_metric,
        prompt: "show MRR",
        timestamp: DateTime.utc_now()
      }

      assert result.layout_key == nil
    end
  end

  describe "error/2 sanitization (T4.3)" do
    test "does not leak raw Postgres detail for query_failed errors" do
      detail = ~s(relation "users" does not exist)
      result = Result.error({:query_failed, detail}, "show users")

      refute result.error =~ "relation"
      refute result.error =~ "users"
      refute result.description =~ "relation"

      assert result.error == "The database query failed. Please rephrase your question."
      assert result.type == :error
    end

    test "scope_violation produces a safe, generic message" do
      result = Result.error(:scope_violation, "all customers")
      assert result.error == "This query was blocked because it wasn't scoped to your data."
    end
  end
end
