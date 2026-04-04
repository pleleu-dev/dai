defmodule Dai.SchemaExplorerComponents do
  @moduledoc false
  use Phoenix.Component

  alias Dai.Icons

  attr :schema_explorer, :map, required: true

  def empty_state(assigns) do
    tables = assigns.schema_explorer.tables

    assigns =
      assign(assigns,
        tables: tables,
        suggestions: assigns.schema_explorer.suggestions,
        table_count: length(tables),
        column_count:
          Map.get_lazy(assigns.schema_explorer, :total_columns, fn ->
            tables |> Enum.flat_map(& &1.columns) |> length()
          end),
        relationship_count:
          Map.get_lazy(assigns.schema_explorer, :total_relationships, fn ->
            tables |> Enum.flat_map(& &1.associations) |> length()
          end)
      )

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
                      {Map.get(table, :column_count, length(table.columns))} cols
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

  attr :schema_panel_open, :boolean, required: true
  attr :schema_explorer, :map, required: true
  attr :explorer_focus, :list, required: true
  attr :explorer_suggestions, :list, required: true
  attr :explorer_loading, :boolean, required: true

  def schema_panel(assigns) do
    ~H"""
    <div
      :if={@schema_panel_open}
      id="schema-panel-content"
      class="fixed top-0 right-0 h-full w-80 z-40 bg-base-100 border-l border-base-300 shadow-xl overflow-y-auto p-4"
    >
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-base font-bold">Schema Explorer</h2>
        <button
          phx-click="toggle_schema_panel"
          class="btn btn-ghost btn-sm btn-circle"
          aria-label="Close schema panel"
        >
          <Icons.x_mark class="size-4" />
        </button>
      </div>
      <.panel_table_list :if={@explorer_focus == []} schema_explorer={@schema_explorer} />
      <.panel_table_detail
        :if={@explorer_focus != []}
        schema_explorer={@schema_explorer}
        explorer_focus={@explorer_focus}
        explorer_suggestions={@explorer_suggestions}
        explorer_loading={@explorer_loading}
      />
    </div>
    """
  end

  attr :schema_explorer, :map, required: true

  defp panel_table_list(assigns) do
    assigns = assign(assigns, :tables, assigns.schema_explorer.tables)

    ~H"""
    <div class="flex flex-col gap-1">
      <button
        :for={table <- @tables}
        phx-click="select_table"
        phx-value-name={table.name}
        class="btn btn-ghost btn-sm justify-between w-full text-left"
      >
        <span class="font-medium truncate">{table.name}</span>
        <span class="flex items-center gap-1.5">
          <span class="badge badge-ghost badge-xs">
            {Map.get(table, :column_count, length(table.columns))} cols
          </span>
          <span class="badge badge-ghost badge-xs">
            {Map.get(table, :association_count, length(table.associations))} rels
          </span>
          <span class="badge badge-ghost badge-xs">{format_row_count(table.row_count)} rows</span>
        </span>
      </button>
    </div>
    """
  end

  attr :schema_explorer, :map, required: true
  attr :explorer_focus, :list, required: true
  attr :explorer_suggestions, :list, required: true
  attr :explorer_loading, :boolean, required: true

  defp panel_table_detail(assigns) do
    all_tables = assigns.schema_explorer.tables
    focus_set = MapSet.new(assigns.explorer_focus)
    focused_tables = Enum.filter(all_tables, &(&1.name in focus_set))

    related_names =
      focused_tables
      |> Enum.flat_map(fn t -> Enum.map(t.associations, & &1.target) end)
      |> MapSet.new()
      |> MapSet.difference(focus_set)

    related_tables = Enum.filter(all_tables, &(&1.name in related_names))

    assigns =
      assign(assigns,
        focused_tables: focused_tables,
        related_tables: related_tables
      )

    ~H"""
    <div>
      <button phx-click="reset_explorer" class="btn btn-ghost btn-sm gap-1 mb-3">
        <Icons.arrow_left class="size-4" /> All tables
      </button>

      <div id="explorer-focus" class="flex flex-wrap gap-1.5 mb-4">
        <span :for={name <- @explorer_focus} class="badge badge-primary gap-1">
          {name}
          <button
            phx-click="deselect_table"
            phx-value-name={name}
            class="btn btn-ghost btn-circle btn-xs"
            aria-label={"Remove #{name}"}
          >
            <Icons.x_mark class="size-3" />
          </button>
        </span>
      </div>

      <div :for={table <- @focused_tables} class="collapse collapse-arrow bg-base-200/50 mb-2">
        <input type="checkbox" checked />
        <div class="collapse-title font-medium text-sm">{table.name}</div>
        <div class="collapse-content">
          <table class="table table-xs">
            <thead>
              <tr>
                <th>Column</th>
                <th>Type</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={col <- table.columns}>
                <td>{col.name}</td>
                <td class="text-base-content/50">{col.type}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div :if={@related_tables != []} class="mt-4">
        <h4 class="text-xs font-semibold text-base-content/50 uppercase mb-2">Also Related</h4>
        <ul class="menu menu-sm">
          <li :for={table <- @related_tables}>
            <button
              phx-click="select_table"
              phx-value-name={table.name}
              class="flex justify-between"
            >
              <span>{table.name}</span>
              <span class="text-xs text-primary">+ add</span>
            </button>
          </li>
        </ul>
      </div>

      <div class="mt-4">
        <h4 class="text-xs font-semibold text-base-content/50 uppercase mb-2">Suggestions</h4>
        <div :if={@explorer_loading} class="flex justify-center py-4">
          <span class="loading loading-dots loading-sm"></span>
        </div>
        <.suggestion_list
          :if={!@explorer_loading && @explorer_suggestions != []}
          suggestions={@explorer_suggestions}
        />
        <p
          :if={!@explorer_loading && @explorer_suggestions == []}
          class="text-sm text-base-content/40"
        >
          No suggestions available.
        </p>
      </div>
    </div>
    """
  end

  defp format_row_count(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_row_count(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_row_count(n), do: "#{n}"
end
