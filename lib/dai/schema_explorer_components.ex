defmodule Dai.SchemaExplorerComponents do
  @moduledoc false
  use Phoenix.Component

  alias Dai.Icons

  attr :schema_explorer, :map, required: true

  def empty_state(assigns) do
    tables = assigns.schema_explorer.tables
    suggestions = assigns.schema_explorer.suggestions

    total_columns = tables |> Enum.flat_map(& &1.columns) |> length()
    total_relationships = tables |> Enum.flat_map(& &1.associations) |> length()

    assigns =
      assigns
      |> assign(:tables, tables)
      |> assign(:suggestions, suggestions)
      |> assign(:table_count, length(tables))
      |> assign(:column_count, total_columns)
      |> assign(:relationship_count, total_relationships)

    ~H"""
    <div id="empty-state" class="hidden only:block col-span-full">
      <div class="hero py-12">
        <div class="hero-content flex-col w-full max-w-5xl">
          <div class="text-center mb-8">
            <div class="text-base-content/20 mb-4">
              <Icons.chart_bar class="size-16 mx-auto" />
            </div>
            <h2 class="text-2xl font-semibold text-base-content/60 mb-2">
              Ask anything about your data
            </h2>
            <p class="text-base-content/40 text-sm max-w-md mx-auto">
              Explore your database schema below, or type a question to get started.
            </p>
          </div>

          <div id="schema-stats" class="stats shadow mb-8 w-full max-w-lg">
            <div id="stat-tables" class="stat">
              <div class="stat-title">Tables</div>
              <div class="stat-value text-primary">{@table_count}</div>
            </div>
            <div id="stat-columns" class="stat">
              <div class="stat-title">Columns</div>
              <div class="stat-value text-secondary">{@column_count}</div>
            </div>
            <div id="stat-relationships" class="stat">
              <div class="stat-title">Relationships</div>
              <div class="stat-value text-accent">{@relationship_count}</div>
            </div>
          </div>

          <div id="schema-tables" class="w-full mb-8">
            <h3 class="text-sm font-medium text-base-content/50 mb-3">Your tables</h3>
            <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
              <div
                :for={table <- @tables}
                class="card card-compact bg-base-200/50 border border-base-300"
              >
                <div class="card-body">
                  <h4 class="card-title text-sm">{table.name}</h4>
                  <div class="flex flex-wrap gap-1">
                    <span class="badge badge-ghost badge-xs">
                      {length(table.columns)} cols
                    </span>
                    <span class="badge badge-ghost badge-xs">
                      {format_row_count(table.row_count)} rows
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <.suggestion_list :if={@suggestions != []} suggestions={@suggestions} />

          <p class="text-base-content/30 text-xs mt-4">
            Press <kbd class="kbd kbd-xs">Tab</kbd>
            to autocomplete or <kbd class="kbd kbd-xs">Enter</kbd>
            to submit
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :suggestions, :list, required: true

  def suggestion_list(assigns) do
    ~H"""
    <div id="schema-suggestions" class="w-full">
      <h3 class="text-sm font-medium text-base-content/50 mb-3 flex items-center gap-1.5">
        <Icons.light_bulb class="size-4" />
        <span>Suggested questions</span>
      </h3>
      <div class="flex flex-col gap-2">
        <div
          :for={suggestion <- @suggestions}
          class="flex items-center gap-2 group rounded-lg border border-base-300 bg-base-200/30 px-3 py-2"
        >
          <button
            type="button"
            phx-click="run_suggestion"
            phx-value-text={suggestion.text}
            class="btn btn-ghost btn-xs btn-circle opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
            aria-label="Run suggestion"
          >
            <Icons.play class="size-3" />
          </button>
          <span class="flex-1 text-sm text-base-content/70">{suggestion.text}</span>
          <div class="flex gap-1">
            <span
              :for={table <- suggestion.tables}
              class="badge badge-ghost badge-xs"
            >
              {table}
            </span>
          </div>
          <button
            type="button"
            phx-click="edit_suggestion"
            phx-value-text={suggestion.text}
            class="btn btn-ghost btn-xs btn-circle opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
            aria-label="Edit suggestion"
          >
            <Icons.pencil class="size-3" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp format_row_count(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_row_count(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_row_count(n), do: "#{n}"
end
