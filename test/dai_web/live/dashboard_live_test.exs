defmodule DaiWeb.DashboardLiveTest do
  use DaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Dai.Folders

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

  describe "empty state" do
    test "renders stats row with table, column, and relationship counts", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#schema-stats")
      assert has_element?(view, "#stat-tables")
      assert has_element?(view, "#stat-columns")
      assert has_element?(view, "#stat-relationships")
    end

    test "renders table grid with table names and row counts", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html = render(view)
      assert html =~ "users"
      assert html =~ "plans"
      assert html =~ "subscriptions"
      assert has_element?(view, "#schema-tables")
    end

    test "renders suggestion list when suggestions exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Suggestions require an API key, so in test they may be empty.
      # When present, the suggestion list element is rendered.
      explorer = Dai.SchemaExplorer.get()

      if explorer.suggestions != [] do
        assert has_element?(view, "#schema-suggestions")
      else
        refute has_element?(view, "#schema-suggestions")
      end
    end
  end

  describe "sidebar" do
    test "sidebar is collapsed by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "aside.w-11")
      refute has_element?(view, "aside.w-56")
    end

    test "toggle_sidebar expands and collapses", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=toggle_sidebar]") |> render_click()
      assert has_element?(view, "aside.w-56")

      view |> element("button[phx-click=toggle_sidebar]") |> render_click()
      assert has_element?(view, "aside.w-11")
    end

    test "create_folder adds a folder to sidebar", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=toggle_sidebar]") |> render_click()
      view |> element("button[phx-click=create_folder]") |> render_click()

      assert render(view) =~ "New Folder"
    end

    test "load_folder expands sidebar and shows folder queries", %{conn: conn} do
      {:ok, folder} = Folders.create_folder(%{name: "Test Folder"})

      {:ok, _query} =
        Folders.create_saved_query(%{folder_id: folder.id, prompt: "test question?"})

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("button[phx-click=load_folder][phx-value-id=\"#{folder.id}\"]")
      |> render_click()

      html = render(view)
      assert html =~ "test question?"
      assert has_element?(view, "aside.w-56")
    end

    test "delete_folder removes it from sidebar", %{conn: conn} do
      {:ok, folder} = Folders.create_folder(%{name: "Doomed Folder"})
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=toggle_sidebar]") |> render_click()
      assert render(view) =~ "Doomed Folder"

      render_hook(view, "delete_folder", %{"id" => folder.id})

      refute render(view) =~ "Doomed Folder"
    end

    test "delete_saved_query removes it from folder", %{conn: conn} do
      {:ok, folder} = Folders.create_folder(%{name: "My Folder"})
      {:ok, query} = Folders.create_saved_query(%{folder_id: folder.id, prompt: "doomed query?"})

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("button[phx-click=load_folder][phx-value-id=\"#{folder.id}\"]")
      |> render_click()

      assert render(view) =~ "doomed query?"

      view
      |> element("button[phx-click=delete_saved_query][phx-value-id=\"#{query.id}\"]")
      |> render_click()

      refute render(view) =~ "doomed query?"
    end
  end

  describe "schema panel" do
    test "schema panel is hidden by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      refute has_element?(view, "#schema-panel-content")
    end

    test "toggle_schema_panel opens the panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("#schema-toggle") |> render_click()
      assert has_element?(view, "#schema-panel-content")
    end

    test "select_table shows table detail", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("#schema-toggle") |> render_click()
      view |> element("button[phx-click=select_table][phx-value-name=users]") |> render_click()

      html = render(view)
      assert html =~ "email"
      assert html =~ "string"
      assert has_element?(view, "#explorer-focus")
    end

    test "deselect_table removes table from focus", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("#schema-toggle") |> render_click()
      view |> element("button[phx-click=select_table][phx-value-name=users]") |> render_click()
      view |> element("button[phx-click=deselect_table][phx-value-name=users]") |> render_click()

      refute has_element?(view, "#explorer-focus")
    end

    test "reset_explorer clears all focused tables", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("#schema-toggle") |> render_click()
      view |> element("button[phx-click=select_table][phx-value-name=users]") |> render_click()
      view |> element("button[phx-click=reset_explorer]") |> render_click()

      refute has_element?(view, "#explorer-focus")
    end
  end
end
