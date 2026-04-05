defmodule Dai.DashboardLiveLayoutTest do
  use DaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "two-panel layout" do
    test "renders dashboard-panels container", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#dashboard-panels")
    end

    test "renders GridStack container with hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#results[phx-hook='DaiGridStack']")
    end

    test "renders horizontal resizer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#main-resizer[phx-hook='DaiPanelResizer']")
    end

    test "renders vertical resizer in right panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#right-resizer[phx-hook='DaiPanelResizer']")
    end

    test "renders right panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#right-panel")
    end

    test "renders query form in left panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#query-form")
    end
  end

  describe "layout persistence events" do
    test "layout_changed event persists without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      cards = [%{"layout_key" => "abc123", "x" => 1, "y" => 0, "w" => 2, "h" => 2}]
      render_hook(view, "layout_changed", %{"cards" => cards})

      assert has_element?(view, "#dashboard-panels")
    end

    test "panel_resized event persists without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "panel_resized", %{"name" => "main_split", "size" => 60})

      assert has_element?(view, "#dashboard-panels")
    end
  end
end
