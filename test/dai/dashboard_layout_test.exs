defmodule Dai.DashboardLayoutTest do
  use Dai.DataCase, async: true

  alias Dai.DashboardLayout

  describe "layout_key/1" do
    test "normalizes whitespace and case" do
      assert DashboardLayout.layout_key("Show me MRR") ==
               DashboardLayout.layout_key("  show me mrr  ")
    end

    test "different prompts produce different keys" do
      refute DashboardLayout.layout_key("show MRR") ==
               DashboardLayout.layout_key("show churn")
    end

    test "returns a 16-char hex string" do
      key = DashboardLayout.layout_key("test prompt")
      assert String.length(key) == 16
      assert key =~ ~r/^[0-9a-f]{16}$/
    end
  end

  describe "get_layouts/1 and save_layout/3" do
    test "returns empty map when no layouts saved" do
      assert DashboardLayout.get_layouts("user-1") == %{}
    end

    test "saves and retrieves a layout" do
      {:ok, _} = DashboardLayout.save_layout("user-1", "abc123", %{x: 1, y: 2, w: 2, h: 2})

      layouts = DashboardLayout.get_layouts("user-1")
      assert layouts["abc123"] == %{x: 1, y: 2, w: 2, h: 2}
    end

    test "upserts existing layout" do
      {:ok, _} = DashboardLayout.save_layout("user-1", "abc123", %{x: 0, y: 0, w: 1, h: 1})
      {:ok, _} = DashboardLayout.save_layout("user-1", "abc123", %{x: 3, y: 1, w: 2, h: 2})

      layouts = DashboardLayout.get_layouts("user-1")
      assert layouts["abc123"] == %{x: 3, y: 1, w: 2, h: 2}
    end

    test "isolates layouts by user_token" do
      {:ok, _} = DashboardLayout.save_layout("user-1", "key1", %{x: 0, y: 0, w: 1, h: 1})
      {:ok, _} = DashboardLayout.save_layout("user-2", "key2", %{x: 1, y: 1, w: 2, h: 2})

      assert Map.keys(DashboardLayout.get_layouts("user-1")) == ["key1"]
      assert Map.keys(DashboardLayout.get_layouts("user-2")) == ["key2"]
    end
  end

  describe "save_layouts/2" do
    test "batch saves multiple cards" do
      cards = [
        %{"layout_key" => "k1", "x" => 0, "y" => 0, "w" => 1, "h" => 1},
        %{"layout_key" => "k2", "x" => 1, "y" => 0, "w" => 2, "h" => 2}
      ]

      DashboardLayout.save_layouts("user-1", cards)

      layouts = DashboardLayout.get_layouts("user-1")
      assert map_size(layouts) == 2
      assert layouts["k1"] == %{x: 0, y: 0, w: 1, h: 1}
      assert layouts["k2"] == %{x: 1, y: 0, w: 2, h: 2}
    end
  end
end
