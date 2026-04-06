defmodule Dai.PushCardTest do
  use ExUnit.Case, async: true

  alias Dai.AI.Result

  describe "rendered_to_string/1 for result_card" do
    test "renders error card with retry button" do
      result = %Result{
        id: "test1",
        type: :error,
        prompt: "test query",
        timestamp: DateTime.utc_now(),
        error: "Something went wrong",
        layout_key: "abc123"
      }

      html = render_card(result)

      assert html =~ "Something went wrong"
      assert html =~ ~s(phx-click="retry")
      assert html =~ ~s(phx-click="dismiss")
      assert html =~ ~s(phx-value-id="test1")
    end

    test "renders kpi_metric card with value" do
      result = %Result{
        id: "test2",
        type: :kpi_metric,
        prompt: "count users",
        timestamp: DateTime.utc_now(),
        title: "Total Users",
        description: "Count of users",
        data: %{columns: ["count"], rows: [%{"count" => 200}]},
        config: %{"format" => "number", "label" => "Users"},
        layout_key: "def456"
      }

      html = render_card(result)

      assert html =~ "200"
      assert html =~ "Total Users"
      assert html =~ ~s(phx-click="dismiss")
    end

    test "renders data_table card with columns and rows" do
      result = %Result{
        id: "test3",
        type: :data_table,
        prompt: "list users",
        timestamp: DateTime.utc_now(),
        title: "Users",
        data: %{
          columns: ["name", "email"],
          rows: [
            %{"name" => "Alice", "email" => "alice@example.com"},
            %{"name" => "Bob", "email" => "bob@example.com"}
          ]
        },
        config: %{},
        layout_key: "ghi789"
      }

      html = render_card(result)

      assert html =~ "Alice"
      assert html =~ "bob@example.com"
      assert html =~ "name"
      assert html =~ "email"
    end

    test "renders clarification card with form" do
      result = %Result{
        id: "test4",
        type: :clarification,
        prompt: "show data",
        timestamp: DateTime.utc_now(),
        question: "Which table do you mean?",
        layout_key: "jkl012"
      }

      html = render_card(result)

      assert html =~ "Which table do you mean?"
      assert html =~ ~s(phx-submit="query")
      assert html =~ ~s(name="prompt")
    end

    test "all rendered cards contain dismiss button with id" do
      results = [
        %Result{
          id: "e1",
          type: :error,
          prompt: "p",
          timestamp: DateTime.utc_now(),
          error: "err",
          layout_key: "a"
        },
        %Result{
          id: "k1",
          type: :kpi_metric,
          prompt: "p",
          timestamp: DateTime.utc_now(),
          title: "T",
          data: %{columns: ["v"], rows: [%{"v" => 1}]},
          config: %{},
          layout_key: "b"
        },
        %Result{
          id: "d1",
          type: :data_table,
          prompt: "p",
          timestamp: DateTime.utc_now(),
          title: "T",
          data: %{columns: ["c"], rows: [%{"c" => 1}]},
          config: %{},
          layout_key: "c"
        },
        %Result{
          id: "c1",
          type: :clarification,
          prompt: "p",
          timestamp: DateTime.utc_now(),
          question: "Q?",
          layout_key: "d"
        }
      ]

      for result <- results do
        html = render_card(result)
        assert html =~ ~s(phx-click="dismiss"), "#{result.type} card missing dismiss button"

        assert html =~ ~s(phx-value-id="#{result.id}"),
               "#{result.type} card missing phx-value-id"
      end
    end
  end

  defp render_card(result) do
    assigns = %{result: result, folders: []}

    Dai.DashboardComponents.result_card(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
