defmodule Dai.AI.SqlExecutorTest do
  use Dai.DataCase, async: true

  alias Dai.AI.SqlExecutor

  describe "execute/1" do
    test "executes a valid SELECT and returns columns and rows" do
      plan = %{"sql" => "SELECT 1 AS num, 'hello' AS greeting"}
      assert {:ok, result} = SqlExecutor.execute(plan)
      assert result.columns == ["num", "greeting"]
      assert result.rows == [%{"num" => 1, "greeting" => "hello"}]
    end

    test "returns multiple rows as list of maps" do
      plan = %{"sql" => "SELECT x FROM generate_series(1, 3) AS x"}
      assert {:ok, result} = SqlExecutor.execute(plan)
      assert length(result.rows) == 3
      assert Enum.map(result.rows, & &1["x"]) == [1, 2, 3]
    end

    test "normalizes raw UUID binaries to formatted strings" do
      plan = %{"sql" => "SELECT gen_random_uuid() AS id"}
      assert {:ok, result} = SqlExecutor.execute(plan)
      [row] = result.rows
      assert is_binary(row["id"])

      assert Regex.match?(
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
               row["id"]
             )
    end

    test "returns error for invalid SQL" do
      plan = %{"sql" => "SELECT * FROM nonexistent_table_xyz"}
      assert {:error, {:query_failed, message}} = SqlExecutor.execute(plan)
      assert is_binary(message)
    end
  end
end
