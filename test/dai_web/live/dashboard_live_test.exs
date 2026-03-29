defmodule DaiWeb.DashboardLiveTest do
  use DaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "mount" do
    test "renders the dashboard page with query form and empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#query-form")
      assert has_element?(view, "#results")
      assert has_element?(view, "#empty-state")
    end
  end

  describe "query submission" do
    test "shows loading state on submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> form("#query-form", query: %{prompt: ""}) |> render_submit()
      refute has_element?(view, ".loading-spinner")
    end
  end
end
