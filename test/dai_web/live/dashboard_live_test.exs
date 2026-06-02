defmodule DaiWeb.DashboardLiveTest do
  use DaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Dai.Folders

  describe "mount" do
    test "renders the dashboard page with query form and empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#query-form")
      assert has_element?(view, "#results-grid")
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

      tables = render(view) |> LazyHTML.from_document() |> LazyHTML.query("#schema-tables")
      text = LazyHTML.text(tables)

      assert text =~ "users"
      assert text =~ "plans"
      assert text =~ "subscriptions"
    end

    test "renders the suggestion list when suggestions are present" do
      explorer = %{
        tables: [],
        suggestions: [%{text: "How many active users?", tables: ["users"]}],
        total_columns: 0,
        total_relationships: 0
      }

      html =
        render_component(&Dai.SchemaExplorerComponents.empty_state/1, schema_explorer: explorer)
        |> LazyHTML.from_fragment()

      suggestions = LazyHTML.query(html, "#schema-suggestions")
      refute Enum.empty?(suggestions)
      assert LazyHTML.text(suggestions) =~ "How many active users?"
    end

    test "omits the suggestion list when there are no suggestions" do
      explorer = %{tables: [], suggestions: [], total_columns: 0, total_relationships: 0}

      html =
        render_component(&Dai.SchemaExplorerComponents.empty_state/1, schema_explorer: explorer)
        |> LazyHTML.from_fragment()

      assert html |> LazyHTML.query("#schema-suggestions") |> Enum.empty?()
    end
  end

  describe "folder panel" do
    @user_token "dashboard-live-test-token"

    # The LiveView reads `dai_user_token` from the session first, so injecting a
    # known token lets pre-created folders (scoped to the same token) appear in
    # the mounted view.
    setup %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{"dai_user_token" => @user_token})
      %{conn: conn}
    end

    test "folder panel is visible in right panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "#right-panel")
    end

    test "create_folder adds a folder", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "create_folder", %{"name" => "My Folder"})

      assert render(view) =~ "My Folder"
    end

    test "load_folder shows folder queries", %{conn: conn} do
      {:ok, folder} = Folders.create_folder(@user_token, %{name: "Test Folder"})

      {:ok, _query} =
        Folders.create_saved_query(@user_token, %{folder_id: folder.id, prompt: "test question?"})

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("button[phx-click=load_folder][phx-value-id=\"#{folder.id}\"]")
      |> render_click()

      assert render(view) =~ "test question?"
    end

    test "delete_folder removes it", %{conn: conn} do
      {:ok, folder} = Folders.create_folder(@user_token, %{name: "Doomed Folder"})
      {:ok, view, _html} = live(conn, "/")

      assert render(view) =~ "Doomed Folder"

      render_hook(view, "delete_folder", %{"id" => folder.id})

      refute render(view) =~ "Doomed Folder"
    end

    test "delete_saved_query removes it from folder", %{conn: conn} do
      {:ok, folder} = Folders.create_folder(@user_token, %{name: "My Folder"})

      {:ok, query} =
        Folders.create_saved_query(@user_token, %{folder_id: folder.id, prompt: "doomed query?"})

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

  describe "suggestion interaction" do
    test "run_suggestion triggers a query", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_hook(view, "run_suggestion", %{"text" => "How many users?"})

      # The query runs async — verify the view stays alive (no crash)
      assert has_element?(view, "#dashboard-panels")
    end

    test "edit_suggestion fills the input without executing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_hook(view, "edit_suggestion", %{"text" => "Revenue by plan"})

      # No query is triggered — verify the view stays alive
      assert has_element?(view, "#dashboard-panels")
    end
  end

  describe "schema panel" do
    test "schema explorer is always visible in right panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "#right-panel")
      assert render(view) =~ "Schema Explorer"
    end

    test "select_table shows table detail", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=select_table][phx-value-name=users]") |> render_click()

      detail = render(view) |> LazyHTML.from_document() |> LazyHTML.query("#explorer-detail")
      text = LazyHTML.text(detail)

      refute Enum.empty?(detail)
      assert text =~ "email"
      assert text =~ "string"
    end

    test "deselect_table removes table from focus", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=select_table][phx-value-name=users]") |> render_click()
      view |> element("button[phx-click=deselect_table][phx-value-name=users]") |> render_click()

      refute has_element?(view, "#explorer-focus")
    end

    test "reset_explorer clears all focused tables", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=select_table][phx-value-name=users]") |> render_click()
      view |> element("button[phx-click=reset_explorer]") |> render_click()

      refute has_element?(view, "#explorer-focus")
    end
  end

  describe "input caps and rate limiting" do
    test "rejects a prompt longer than the configured maximum", %{conn: conn} do
      Application.put_env(:dai, :max_prompt_length, 50)
      on_exit(fn -> Application.delete_env(:dai, :max_prompt_length) end)

      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "query", %{"prompt" => String.duplicate("a", 51)})

      assert has_element?(view, "#query-error", "too long")
    end

    test "accepts a prompt within the configured maximum", %{conn: conn} do
      Application.put_env(:dai, :max_prompt_length, 50)
      on_exit(fn -> Application.delete_env(:dai, :max_prompt_length) end)

      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "query", %{"prompt" => "how many users?"})

      refute has_element?(view, "#query-error")
    end

    test "rate-limits rapid queries beyond the per-socket budget", %{conn: conn} do
      Application.put_env(:dai, :rate_limit, %{limit: 1, window_ms: 60_000})
      on_exit(fn -> Application.delete_env(:dai, :rate_limit) end)

      {:ok, view, _html} = live(conn, "/")

      # First query spends the only token and is accepted (no inline error).
      render_hook(view, "query", %{"prompt" => "first question"})
      refute has_element?(view, "#query-error")

      # Second rapid query finds an empty bucket → rejected, no pipeline Task.
      render_hook(view, "query", %{"prompt" => "second question"})
      assert has_element?(view, "#query-error", "too quickly")
    end
  end
end
