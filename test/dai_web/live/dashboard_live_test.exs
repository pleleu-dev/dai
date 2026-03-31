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
      {:ok, _query} = Folders.create_saved_query(%{folder_id: folder.id, prompt: "test question?"})

      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=load_folder][phx-value-id=\"#{folder.id}\"]") |> render_click()

      html = render(view)
      assert html =~ "test question?"
      assert has_element?(view, "aside.w-56")
    end

    test "delete_folder removes it from sidebar", %{conn: conn} do
      {:ok, folder} = Folders.create_folder(%{name: "Doomed Folder"})
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=toggle_sidebar]") |> render_click()
      assert render(view) =~ "Doomed Folder"

      view |> element("button[phx-click=delete_folder][phx-value-id=\"#{folder.id}\"]") |> render_click()
      refute render(view) =~ "Doomed Folder"
    end

    test "delete_saved_query removes it from folder", %{conn: conn} do
      {:ok, folder} = Folders.create_folder(%{name: "My Folder"})
      {:ok, query} = Folders.create_saved_query(%{folder_id: folder.id, prompt: "doomed query?"})

      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=load_folder][phx-value-id=\"#{folder.id}\"]") |> render_click()
      assert render(view) =~ "doomed query?"

      view |> element("button[phx-click=delete_saved_query][phx-value-id=\"#{query.id}\"]") |> render_click()
      refute render(view) =~ "doomed query?"
    end
  end
end
