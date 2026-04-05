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
end
