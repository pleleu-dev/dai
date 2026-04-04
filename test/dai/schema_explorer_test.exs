defmodule Dai.SchemaExplorerTest do
  use Dai.DataCase, async: true

  alias Dai.SchemaExplorer

  describe "get/0" do
    test "returns a map with tables and suggestions keys" do
      data = SchemaExplorer.get()
      assert is_map(data)
      assert Map.has_key?(data, :tables)
      assert Map.has_key?(data, :suggestions)
    end

    test "tables contain expected fields" do
      %{tables: tables} = SchemaExplorer.get()
      assert length(tables) > 0

      table = Enum.find(tables, &(&1.name == "users"))
      assert table != nil
      assert is_list(table.columns)
      assert is_list(table.primary_key)
      assert is_list(table.associations)
      assert is_integer(table.row_count)
    end

    test "table columns have name and type" do
      %{tables: tables} = SchemaExplorer.get()
      table = Enum.find(tables, &(&1.name == "users"))
      col = Enum.find(table.columns, &(&1.name == "email"))
      assert col != nil
      assert col.type == "string"
    end

    test "table associations have type, name, and target" do
      %{tables: tables} = SchemaExplorer.get()
      table = Enum.find(tables, &(&1.name == "users"))
      assoc = Enum.find(table.associations, &(&1.name == :subscriptions))
      assert assoc != nil
      assert assoc.type == :has_many
      assert assoc.target == "subscriptions"
    end

    test "row counts are non-negative integers" do
      %{tables: tables} = SchemaExplorer.get()

      Enum.each(tables, fn table ->
        assert is_integer(table.row_count)
        assert table.row_count >= 0
      end)
    end

    test "suggestions is a list (may be empty if API unavailable)" do
      %{suggestions: suggestions} = SchemaExplorer.get()
      assert is_list(suggestions)
    end
  end

  describe "suggest/1" do
    test "returns a list for given table names" do
      result = SchemaExplorer.suggest(["users", "subscriptions"])
      assert is_list(result)
    end

    test "returns empty list for empty table selection" do
      assert SchemaExplorer.suggest([]) == []
    end

    test "caches results for same table combination" do
      result1 = SchemaExplorer.suggest(["users"])
      result2 = SchemaExplorer.suggest(["users"])
      assert result1 == result2
    end

    test "same tables in different order hit same cache" do
      result1 = SchemaExplorer.suggest(["users", "plans"])
      result2 = SchemaExplorer.suggest(["plans", "users"])
      assert result1 == result2
    end
  end

  describe "reload/0" do
    test "clears on-demand suggestion cache" do
      SchemaExplorer.suggest(["users"])
      assert :ets.info(:dai_explorer_cache, :size) > 0
      SchemaExplorer.reload()
      assert :ets.info(:dai_explorer_cache, :size) == 0
    end
  end

  describe "boot suggestions structure" do
    test "each suggestion has text and tables keys when present" do
      %{suggestions: suggestions} = SchemaExplorer.get()

      Enum.each(suggestions, fn suggestion ->
        assert Map.has_key?(suggestion, :text)
        assert Map.has_key?(suggestion, :tables)
        assert is_binary(suggestion.text)
        assert is_list(suggestion.tables)
      end)
    end
  end
end
