# Schema Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give users visibility into the database schema via a rich empty-state onboarding view and a persistent schema explorer drawer, with AI-generated query suggestions.

**Architecture:** New `Dai.SchemaExplorer` GenServer enriches `SchemaContext` data with row counts and AI suggestions, cached in `:persistent_term` (boot) and ETS (on-demand). `DashboardLive` gains new assigns and events for the empty state and schema panel. New render helpers go in a dedicated `Dai.SchemaExplorerComponents` module to keep `DashboardComponents` focused on result cards.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, daisyUI 5, Req (Claude API)

---

## File Structure

| Action | File | Responsibility |
|---|---|---|
| Create | `lib/dai/schema_explorer.ex` | GenServer: row counts, boot suggestions, on-demand suggestions, caching |
| Create | `lib/dai/schema_explorer_components.ex` | Function components: empty_state, schema_panel, table_list, table_detail, suggestion_list |
| Modify | `lib/dai/dashboard_live.ex` | New assigns, events, render integration |
| Modify | `lib/dai/application.ex` | Add SchemaExplorer to supervision tree |
| Create | `test/dai/schema_explorer_test.exs` | Unit tests for SchemaExplorer |
| Modify | `test/dai_web/live/dashboard_live_test.exs` | LiveView tests for empty state, schema panel, click-to-explore |

---

### Task 1: SchemaExplorer GenServer — structured schema data + row counts

**Files:**
- Create: `test/dai/schema_explorer_test.exs`
- Create: `lib/dai/schema_explorer.ex`
- Modify: `lib/dai/application.ex`

This task builds the data layer without AI suggestions. It discovers schemas (reusing SchemaContext's logic), structures them as maps, queries row counts, and caches everything.

- [ ] **Step 1: Write failing tests for `SchemaExplorer.get/0`**

```elixir
# test/dai/schema_explorer_test.exs
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
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/dai/schema_explorer_test.exs`
Expected: Compilation error — `Dai.SchemaExplorer` module not found.

- [ ] **Step 3: Implement `Dai.SchemaExplorer`**

```elixir
# lib/dai/schema_explorer.ex
defmodule Dai.SchemaExplorer do
  @moduledoc "Enriches schema context with row counts and AI-generated suggestions."

  @key :dai_schema_explorer

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  def start_link(_opts) do
    data = build_explorer_data()
    :persistent_term.put(@key, data)
    :ignore
  end

  @doc "Returns cached schema explorer data."
  def get do
    :persistent_term.get(@key, %{tables: [], suggestions: []})
  end

  @doc "Rebuilds and recaches schema explorer data."
  def reload do
    :persistent_term.put(@key, build_explorer_data())
    :ok
  end

  defp build_explorer_data do
    schemas = discover_schemas()
    tables = build_tables(schemas)
    %{tables: tables, suggestions: []}
  end

  defp build_tables(schemas) do
    schemas
    |> Task.async_stream(&build_table/1, timeout: 10_000)
    |> Enum.map(fn {:ok, table} -> table end)
    |> Enum.sort_by(& &1.name)
  end

  defp build_table(mod) do
    source = mod.__schema__(:source)

    %{
      name: source,
      columns: extract_columns(mod),
      primary_key: mod.__schema__(:primary_key),
      associations: extract_associations(mod),
      row_count: query_row_count(source)
    }
  end

  defp extract_columns(mod) do
    mod.__schema__(:fields)
    |> Enum.map(fn field ->
      type = mod.__schema__(:type, field)
      %{name: Atom.to_string(field), type: format_type(type)}
    end)
  end

  defp extract_associations(mod) do
    mod.__schema__(:associations)
    |> Enum.map(fn assoc_name ->
      assoc = mod.__schema__(:association, assoc_name)

      %{
        type: assoc_type(assoc),
        name: assoc_name,
        target: assoc.queryable.__schema__(:source)
      }
    end)
  end

  defp query_row_count(table_name) do
    repo = Dai.Config.repo()

    case repo.query("SELECT count(*) FROM #{table_name}") do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end

  defp discover_schemas do
    contexts = Dai.Config.schema_contexts()
    extras = Dai.Config.extra_schemas()

    all_app_modules()
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and
        function_exported?(mod, :__schema__, 1) and
        (matches_context?(mod, contexts) or mod in extras)
    end)
  end

  defp all_app_modules do
    dai_modules =
      case :application.get_key(:dai, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    loaded_modules = Enum.map(:code.all_loaded(), &elem(&1, 0))
    Enum.uniq(dai_modules ++ loaded_modules)
  end

  defp matches_context?(_mod, []), do: true

  defp matches_context?(mod, contexts) do
    mod_string = Atom.to_string(mod)

    Enum.any?(contexts, fn ctx ->
      String.starts_with?(mod_string, Atom.to_string(ctx))
    end)
  end

  defp assoc_type(%Ecto.Association.BelongsTo{}), do: :belongs_to
  defp assoc_type(%Ecto.Association.Has{cardinality: :many}), do: :has_many
  defp assoc_type(%Ecto.Association.Has{cardinality: :one}), do: :has_one
  defp assoc_type(%Ecto.Association.ManyToMany{}), do: :many_to_many
  defp assoc_type(_), do: :unknown

  defp format_type(type) when is_atom(type), do: Atom.to_string(type)
  defp format_type({:parameterized, {Ecto.Embedded, _}}), do: "embedded"
  defp format_type(type), do: inspect(type)
end
```

- [ ] **Step 4: Add SchemaExplorer to supervision tree (after SchemaContext)**

In `lib/dai/application.ex`, add `Dai.SchemaExplorer` right after `Dai.SchemaContext` in the children list:

```elixir
# Find this line:
      Dai.SchemaContext,
# Add after it:
      Dai.SchemaExplorer,
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/dai/schema_explorer_test.exs`
Expected: All 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/dai/schema_explorer.ex lib/dai/application.ex test/dai/schema_explorer_test.exs
git commit -m "feat(explorer): add SchemaExplorer GenServer with row counts"
```

---

### Task 2: SchemaExplorer — AI-generated boot suggestions

**Files:**
- Modify: `test/dai/schema_explorer_test.exs`
- Modify: `lib/dai/schema_explorer.ex`

This task adds boot-time AI suggestion generation. We call Claude with the schema context and parse the JSON array response.

- [ ] **Step 1: Write failing test for boot suggestions**

Add to `test/dai/schema_explorer_test.exs` inside the existing `describe "get/0"` block:

```elixir
    test "suggestions is a list (may be empty if API unavailable)" do
      %{suggestions: suggestions} = SchemaExplorer.get()
      assert is_list(suggestions)
    end
```

Add a new describe block for suggestion structure:

```elixir
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
```

- [ ] **Step 2: Run tests to verify they pass (suggestions list is already `[]`)**

Run: `mix test test/dai/schema_explorer_test.exs`
Expected: All tests pass (suggestions defaults to `[]`, which satisfies both tests).

- [ ] **Step 3: Implement boot suggestion generation**

Add to `lib/dai/schema_explorer.ex`:

Replace the `build_explorer_data/0` function:

```elixir
  defp build_explorer_data do
    schemas = discover_schemas()
    tables = build_tables(schemas)
    schema_context = Dai.SchemaContext.get()
    suggestions = generate_boot_suggestions(schema_context)
    %{tables: tables, suggestions: suggestions}
  end
```

Add these private functions:

```elixir
  @suggestion_prompt """
  Given this database schema:

  %SCHEMA%

  Generate 5-8 example questions that a non-technical user would find useful for exploring this data.
  Prefer questions that span multiple tables (JOINs).
  Return ONLY a valid JSON array, no other text:
  [{"text": "human-readable question", "tables": ["table1", "table2"]}]
  """

  defp generate_boot_suggestions(schema_context) do
    prompt = String.replace(@suggestion_prompt, "%SCHEMA%", schema_context)

    case call_suggestion_api(prompt) do
      {:ok, suggestions} -> suggestions
      {:error, _} -> []
    end
  end

  defp call_suggestion_api(prompt) do
    api_key = Dai.Config.api_key()
    if is_nil(api_key), do: throw(:no_key)

    case Req.post("https://api.anthropic.com/v1/messages",
           json: %{
             model: Dai.Config.model(),
             max_tokens: 1024,
             messages: [%{role: "user", content: prompt}]
           },
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"},
             {"content-type", "application/json"}
           ],
           receive_timeout: 30_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        parse_suggestions(text)

      _ ->
        {:error, :api_error}
    end
  catch
    :no_key -> {:error, :no_api_key}
  end

  defp parse_suggestions(text) do
    case Jason.decode(text) do
      {:ok, list} when is_list(list) ->
        suggestions =
          Enum.map(list, fn item ->
            %{
              text: Map.get(item, "text", ""),
              tables: Map.get(item, "tables", [])
            }
          end)

        {:ok, suggestions}

      _ ->
        {:error, :invalid_json}
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/dai/schema_explorer_test.exs`
Expected: All tests pass. If no API key is set in test env, suggestions will be `[]` which still passes.

- [ ] **Step 5: Commit**

```bash
git add lib/dai/schema_explorer.ex test/dai/schema_explorer_test.exs
git commit -m "feat(explorer): add AI-generated boot suggestions"
```

---

### Task 3: SchemaExplorer — on-demand suggestions with ETS cache

**Files:**
- Modify: `test/dai/schema_explorer_test.exs`
- Modify: `lib/dai/schema_explorer.ex`

This task adds `suggest/1` which generates targeted suggestions for a set of selected tables, cached in ETS.

- [ ] **Step 1: Write failing tests for `suggest/1`**

Add to `test/dai/schema_explorer_test.exs`:

```elixir
  describe "suggest/1" do
    test "returns a list for given table names" do
      result = SchemaExplorer.suggest(["users", "subscriptions"])
      assert is_list(result)
    end

    test "returns empty list for empty table selection" do
      assert SchemaExplorer.suggest([]) == []
    end

    test "caches results for same table combination" do
      # Call twice — second call should hit cache (no API call)
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
      SchemaExplorer.reload()
      # After reload, cache is cleared — next call will regenerate
      data = SchemaExplorer.get()
      assert is_map(data)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/dai/schema_explorer_test.exs`
Expected: `UndefinedFunctionError` for `SchemaExplorer.suggest/1`.

- [ ] **Step 3: Implement `suggest/1` with ETS cache**

Add to `lib/dai/schema_explorer.ex`:

Add ETS table creation in `start_link`:

```elixir
  def start_link(_opts) do
    # Create ETS table for on-demand suggestion cache
    if :ets.whereis(:dai_explorer_cache) == :undefined do
      :ets.new(:dai_explorer_cache, [:set, :public, :named_table])
    end

    data = build_explorer_data()
    :persistent_term.put(@key, data)
    :ignore
  end
```

Update `reload/0` to clear ETS:

```elixir
  def reload do
    if :ets.whereis(:dai_explorer_cache) != :undefined do
      :ets.delete_all_objects(:dai_explorer_cache)
    end

    :persistent_term.put(@key, build_explorer_data())
    :ok
  end
```

Add `suggest/1`:

```elixir
  @doc "Returns AI-generated suggestions for the given table combination. Results are cached."
  def suggest([]), do: []

  def suggest(table_names) do
    cache_key = table_names |> Enum.sort() |> Enum.join(",")

    case ets_lookup(cache_key) do
      {:ok, suggestions} ->
        suggestions

      :miss ->
        suggestions = generate_on_demand_suggestions(table_names)
        ets_put(cache_key, suggestions)
        suggestions
    end
  end

  defp ets_lookup(key) do
    case :ets.lookup(:dai_explorer_cache, key) do
      [{^key, suggestions}] -> {:ok, suggestions}
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp ets_put(key, value) do
    :ets.insert(:dai_explorer_cache, {key, value})
  rescue
    ArgumentError -> :ok
  end

  defp generate_on_demand_suggestions(table_names) do
    %{tables: all_tables} = get()

    selected_schemas =
      all_tables
      |> Enum.filter(&(&1.name in table_names))
      |> Enum.map_join("\n\n", &format_table_for_prompt/1)

    prompt = """
    Given these database tables:

    #{selected_schemas}

    Generate 3-5 example questions a non-technical user would ask about this data.
    Focus on queries that combine these tables.
    Return ONLY a valid JSON array, no other text:
    [{"text": "human-readable question", "tables": ["table1", "table2"]}]
    """

    case call_suggestion_api(prompt) do
      {:ok, suggestions} -> suggestions
      {:error, _} -> []
    end
  end

  defp format_table_for_prompt(table) do
    cols = Enum.map_join(table.columns, ", ", &"#{&1.name} (#{&1.type})")
    assocs = Enum.map_join(table.associations, ", ", &"#{&1.type} #{&1.name} (#{&1.target})")

    assoc_line = if assocs != "", do: "\n  Associations: #{assocs}", else: ""
    "Table: #{table.name}\n  Columns: #{cols}#{assoc_line}"
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/dai/schema_explorer_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/dai/schema_explorer.ex test/dai/schema_explorer_test.exs
git commit -m "feat(explorer): add on-demand suggestions with ETS cache"
```

---

### Task 4: SchemaExplorerComponents — empty state

**Files:**
- Create: `lib/dai/schema_explorer_components.ex`
- Modify: `test/dai_web/live/dashboard_live_test.exs`
- Modify: `lib/dai/dashboard_live.ex`

This task builds the empty state UI with stats, table grid, and suggestions.

- [ ] **Step 1: Write failing LiveView tests for empty state**

Add to `test/dai_web/live/dashboard_live_test.exs` — replace the existing `describe "mount"` block's test with an updated version, and add a new describe block:

```elixir
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

    test "renders suggestion list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "#schema-suggestions")
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/dai_web/live/dashboard_live_test.exs`
Expected: Failures — `#schema-stats`, `#schema-tables`, `#schema-suggestions` elements don't exist.

- [ ] **Step 3: Create `Dai.SchemaExplorerComponents`**

```elixir
# lib/dai/schema_explorer_components.ex
defmodule Dai.SchemaExplorerComponents do
  @moduledoc "Function components for schema discovery UI."

  use Phoenix.Component

  alias Dai.Icons

  attr :schema_explorer, :map, required: true

  def empty_state(assigns) do
    tables = assigns.schema_explorer.tables
    suggestions = assigns.schema_explorer.suggestions

    total_columns = tables |> Enum.map(&length(&1.columns)) |> Enum.sum()

    total_relationships =
      tables |> Enum.map(&length(&1.associations)) |> Enum.sum()

    assigns =
      assign(assigns,
        tables: tables,
        suggestions: suggestions,
        table_count: length(tables),
        column_count: total_columns,
        relationship_count: total_relationships
      )

    ~H"""
    <div id="empty-state" class="hidden only:block col-span-full">
      <div class="hero py-12">
        <div class="hero-content flex-col w-full max-w-2xl">
          <%!-- Stats row --%>
          <div id="schema-stats" class="stats shadow w-full">
            <div id="stat-tables" class="stat place-items-center">
              <div class="stat-title">Tables</div>
              <div class="stat-value text-primary">{@table_count}</div>
            </div>
            <div id="stat-columns" class="stat place-items-center">
              <div class="stat-title">Columns</div>
              <div class="stat-value text-primary">{@column_count}</div>
            </div>
            <div id="stat-relationships" class="stat place-items-center">
              <div class="stat-title">Relationships</div>
              <div class="stat-value text-primary">{@relationship_count}</div>
            </div>
          </div>

          <%!-- Table grid --%>
          <div id="schema-tables" class="w-full mt-6">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Your Tables
            </h3>
            <div class="grid grid-cols-2 md:grid-cols-3 gap-2">
              <div
                :for={table <- @tables}
                class="card card-compact bg-base-200 cursor-default"
              >
                <div class="card-body flex-row items-center justify-between py-2 px-3">
                  <span class="text-sm font-medium">{table.name}</span>
                  <span class="badge badge-ghost badge-sm">
                    {format_row_count(table.row_count)}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <%!-- Suggestions --%>
          <div id="schema-suggestions" class="w-full mt-6">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Suggested Queries
            </h3>
            <.suggestion_list suggestions={@suggestions} />
            <p :if={@suggestions == []} class="text-sm text-base-content/40 text-center py-4">
              Type a question above to get started
            </p>
          </div>

          <%!-- Hint --%>
          <p class="text-xs text-base-content/30 mt-6 text-center">
            Click to run · <kbd class="kbd kbd-xs">pencil</kbd> to edit · Open
            <kbd class="kbd kbd-xs">Schema</kbd>
            to explore tables
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :suggestions, :list, required: true

  def suggestion_list(assigns) do
    ~H"""
    <div class="flex flex-col gap-1.5">
      <div
        :for={suggestion <- @suggestions}
        class="flex items-center gap-2"
      >
        <button
          phx-click="run_suggestion"
          phx-value-text={suggestion.text}
          class="btn btn-ghost btn-sm flex-1 justify-start gap-2 font-normal h-auto py-2"
        >
          <Icons.light_bulb class="size-4 text-warning shrink-0" />
          <span class="text-left">{suggestion.text}</span>
        </button>
        <div class="flex gap-1 shrink-0">
          <span
            :for={table <- suggestion.tables}
            class="badge badge-ghost badge-xs"
          >
            {table}
          </span>
        </div>
        <button
          phx-click="edit_suggestion"
          phx-value-text={suggestion.text}
          class="btn btn-ghost btn-xs btn-circle opacity-40 hover:opacity-100 shrink-0"
          aria-label="Edit suggestion"
        >
          <Icons.pencil class="size-3" />
        </button>
      </div>
    </div>
    """
  end

  defp format_row_count(count) when count >= 1_000_000 do
    "#{Float.round(count / 1_000_000, 1)}M"
  end

  defp format_row_count(count) when count >= 1_000 do
    "#{Float.round(count / 1_000, 1)}K"
  end

  defp format_row_count(count), do: to_string(count)
end
```

- [ ] **Step 4: Add pencil and light_bulb icons to `Dai.Icons`**

Check if `pencil` and `light_bulb` icons exist in `lib/dai/icons.ex`. If not, add them:

```elixir
  def pencil(assigns) do
    assigns = assign_defaults(assigns)

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class={@class}>
      <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
    </svg>
    """
  end

  def light_bulb(assigns) do
    assigns = assign_defaults(assigns)

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class={@class}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 18v-5.25m0 0a6.01 6.01 0 0 0 1.5-.189m-1.5.189a6.01 6.01 0 0 1-1.5-.189m3.75 7.478a12.06 12.06 0 0 1-4.5 0m3.75 2.383a14.406 14.406 0 0 1-3 0M14.25 18v-.192c0-.983.658-1.823 1.508-2.316a7.5 7.5 0 1 0-7.517 0c.85.493 1.509 1.333 1.509 2.316V18" />
    </svg>
    """
  end
```

- [ ] **Step 5: Integrate empty state into `DashboardLive`**

Modify `lib/dai/dashboard_live.ex`:

Add import at the top (after existing imports):

```elixir
  import Dai.SchemaExplorerComponents, only: [empty_state: 1]
```

Add alias:

```elixir
  alias Dai.SchemaExplorer
```

In `mount/3`, add the new assign:

```elixir
       schema_explorer: SchemaExplorer.get(),
```

Replace the `results_grid` component to use the new empty state. In `render/1`, the line:

```elixir
            <.results_grid streams={@streams} folders={@folders} />
```

stays, but modify the `results_grid` private component to use the new empty state:

```elixir
  defp results_grid(assigns) do
    ~H"""
    <div
      id="results"
      phx-update="stream"
      class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
    >
      <.empty_state schema_explorer={@schema_explorer} />
      <div :for={{dom_id, result} <- @streams.results} id={dom_id}>
        <.result_card result={result} folders={@folders} />
      </div>
    </div>
    """
  end
```

Update the `results_grid` attr declarations to add `schema_explorer`:

```elixir
  attr :streams, :any, required: true
  attr :folders, :list, default: []
  attr :schema_explorer, :map, required: true
```

And pass it in `render/1`:

```elixir
            <.results_grid streams={@streams} folders={@folders} schema_explorer={@schema_explorer} />
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/dai_web/live/dashboard_live_test.exs`
Expected: All tests pass, including the new empty state tests.

- [ ] **Step 7: Commit**

```bash
git add lib/dai/schema_explorer_components.ex lib/dai/dashboard_live.ex lib/dai/icons.ex test/dai_web/live/dashboard_live_test.exs
git commit -m "feat(explorer): add rich empty state with stats, tables, and suggestions"
```

---

### Task 5: SchemaExplorerComponents — schema panel drawer

**Files:**
- Modify: `lib/dai/schema_explorer_components.ex`
- Modify: `lib/dai/dashboard_live.ex`
- Modify: `test/dai_web/live/dashboard_live_test.exs`

This task builds the schema panel drawer (all-tables view, single-table detail, multi-table focus).

- [ ] **Step 1: Write failing tests for schema panel**

Add to `test/dai_web/live/dashboard_live_test.exs`:

```elixir
  describe "schema panel" do
    test "schema panel is hidden by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      refute has_element?(view, "#schema-panel.drawer-open")
    end

    test "toggle_schema_panel opens the panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=toggle_schema_panel]") |> render_click()
      assert has_element?(view, "#schema-panel-content")
    end

    test "select_table shows table detail", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=toggle_schema_panel]") |> render_click()
      view |> element("button[phx-click=select_table][phx-value-name=users]") |> render_click()

      html = render(view)
      assert html =~ "email"
      assert html =~ "string"
      assert has_element?(view, "#explorer-focus")
    end

    test "deselect_table removes table from focus", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=toggle_schema_panel]") |> render_click()
      view |> element("button[phx-click=select_table][phx-value-name=users]") |> render_click()
      view |> element("button[phx-click=deselect_table][phx-value-name=users]") |> render_click()

      refute has_element?(view, "#explorer-focus")
    end

    test "reset_explorer clears all focused tables", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element("button[phx-click=toggle_schema_panel]") |> render_click()
      view |> element("button[phx-click=select_table][phx-value-name=users]") |> render_click()
      view |> element("button[phx-click=reset_explorer]") |> render_click()

      refute has_element?(view, "#explorer-focus")
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/dai_web/live/dashboard_live_test.exs`
Expected: Failures — no `toggle_schema_panel` button or `#schema-panel` element.

- [ ] **Step 3: Add schema panel component to `SchemaExplorerComponents`**

Add to `lib/dai/schema_explorer_components.ex`:

```elixir
  attr :schema_panel_open, :boolean, required: true
  attr :schema_explorer, :map, required: true
  attr :explorer_focus, :list, required: true
  attr :explorer_suggestions, :list, required: true
  attr :explorer_loading, :boolean, required: true

  def schema_panel(assigns) do
    ~H"""
    <div id="schema-panel" class={["drawer drawer-end", @schema_panel_open && "drawer-open"]}>
      <input
        id="schema-drawer-toggle"
        type="checkbox"
        class="drawer-toggle"
        checked={@schema_panel_open}
      />
      <div class="drawer-side z-20">
        <label
          for="schema-drawer-toggle"
          phx-click="toggle_schema_panel"
          class="drawer-overlay"
        >
        </label>
        <div id="schema-panel-content" class="menu bg-base-200 min-h-full w-72 p-4">
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

          <%= if @explorer_focus == [] do %>
            <.panel_table_list tables={@schema_explorer.tables} />
          <% else %>
            <.panel_table_detail
              tables={@schema_explorer.tables}
              focus={@explorer_focus}
              suggestions={@explorer_suggestions}
              loading={@explorer_loading}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :tables, :list, required: true

  defp panel_table_list(assigns) do
    ~H"""
    <div>
      <p class="text-xs font-semibold text-base-content/60 uppercase tracking-wide mb-2">Tables</p>
      <div class="flex flex-col gap-1">
        <button
          :for={table <- @tables}
          phx-click="select_table"
          phx-value-name={table.name}
          class="btn btn-ghost btn-sm justify-between font-normal h-auto py-2"
        >
          <div class="text-left">
            <div class="text-sm font-medium">{table.name}</div>
            <div class="text-xs text-base-content/50">
              {length(table.columns)} cols · {length(table.associations)} rels
            </div>
          </div>
          <span class="badge badge-ghost badge-sm">{format_row_count(table.row_count)}</span>
        </button>
      </div>
    </div>
    """
  end

  attr :tables, :list, required: true
  attr :focus, :list, required: true
  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true

  defp panel_table_detail(assigns) do
    focused_tables =
      Enum.filter(assigns.tables, &(&1.name in assigns.focus))

    related_names =
      focused_tables
      |> Enum.flat_map(& &1.associations)
      |> Enum.map(& &1.target)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in assigns.focus))

    related_tables =
      Enum.filter(assigns.tables, &(&1.name in related_names))

    assigns =
      assign(assigns,
        focused_tables: focused_tables,
        related_tables: related_tables
      )

    ~H"""
    <div>
      <button phx-click="reset_explorer" class="btn btn-ghost btn-sm mb-3 gap-1">
        <Icons.arrow_left class="size-3" />
        All tables
      </button>

      <%!-- Focus pills --%>
      <div id="explorer-focus" class="flex flex-wrap gap-1.5 mb-4">
        <span
          :for={name <- @focus}
          class="badge badge-primary gap-1"
        >
          {name}
          <button
            phx-click="deselect_table"
            phx-value-name={name}
            class="hover:opacity-70"
            aria-label={"Remove #{name}"}
          >
            ×
          </button>
        </span>
      </div>

      <%!-- Columns per focused table --%>
      <div :for={table <- @focused_tables} class="mb-3">
        <div
          tabindex="0"
          class="collapse collapse-arrow bg-base-300 rounded-lg"
        >
          <div class="collapse-title text-sm font-medium py-2 min-h-0">
            {table.name} columns
          </div>
          <div class="collapse-content">
            <div class="flex flex-col gap-0.5">
              <div
                :for={col <- table.columns}
                class="flex justify-between text-xs py-0.5"
              >
                <span>{col.name}</span>
                <span class="text-base-content/50">{col.type}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Related tables --%>
      <div :if={@related_tables != []} class="mb-4">
        <p class="text-xs font-semibold text-base-content/60 uppercase tracking-wide mb-2">
          Also Related
        </p>
        <div class="flex flex-col gap-1">
          <button
            :for={table <- @related_tables}
            phx-click="select_table"
            phx-value-name={table.name}
            class="btn btn-ghost btn-xs justify-between font-normal"
          >
            <span>{table.name}</span>
            <span class="text-base-content/40">+ add</span>
          </button>
        </div>
      </div>

      <%!-- Suggestions --%>
      <div class="mt-3">
        <p class="text-xs font-semibold text-base-content/60 uppercase tracking-wide mb-2">
          Suggestions for {Enum.join(@focus, " + ")}
        </p>
        <span :if={@loading} class="loading loading-dots loading-sm text-primary"></span>
        <.suggestion_list :if={not @loading} suggestions={@suggestions} />
        <p
          :if={not @loading and @suggestions == []}
          class="text-xs text-base-content/40 py-2"
        >
          No suggestions available
        </p>
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Add `arrow_left` icon to `Dai.Icons` if missing**

```elixir
  def arrow_left(assigns) do
    assigns = assign_defaults(assigns)

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class={@class}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" />
    </svg>
    """
  end
```

- [ ] **Step 5: Wire schema panel into `DashboardLive`**

In `lib/dai/dashboard_live.ex`:

Update import to include `schema_panel`:

```elixir
  import Dai.SchemaExplorerComponents, only: [empty_state: 1, schema_panel: 1]
```

Add new assigns in `mount/3` (after `schema_explorer`):

```elixir
       schema_panel_open: false,
       explorer_focus: [],
       explorer_suggestions: [],
       explorer_loading: false,
```

In `render/1`, add the schema button in the query input area and the panel component. Replace the render body:

```elixir
  def render(assigns) do
    ~H"""
    <.dai_wrapper host_layout={@dai_host_layout} flash={@flash}>
      <div class="flex h-full">
        <.sidebar
          sidebar_open={@sidebar_open}
          folders={@folders}
          active_folder_id={@active_folder_id}
          folder_queries={@folder_queries}
        />
        <div class="flex-1 min-w-0 p-6">
          <div class="max-w-7xl mx-auto">
            <div class="flex items-center justify-end mb-2">
              <button
                phx-click="toggle_schema_panel"
                class="btn btn-ghost btn-sm gap-1"
              >
                <Icons.table_cells class="size-4" />
                Schema
              </button>
            </div>
            <.query_input form={@form} loading={@loading} />
            <.loading_skeleton :if={@loading} />
            <.results_grid
              streams={@streams}
              folders={@folders}
              schema_explorer={@schema_explorer}
            />
          </div>
        </div>
      </div>
      <.schema_panel
        schema_panel_open={@schema_panel_open}
        schema_explorer={@schema_explorer}
        explorer_focus={@explorer_focus}
        explorer_suggestions={@explorer_suggestions}
        explorer_loading={@explorer_loading}
      />
    </.dai_wrapper>
    """
  end
```

Add new event handlers:

```elixir
  # --- Schema explorer events ---

  def handle_event("toggle_schema_panel", _params, socket) do
    {:noreply, assign(socket, schema_panel_open: !socket.assigns.schema_panel_open)}
  end

  def handle_event("select_table", %{"name" => name}, socket) do
    focus = socket.assigns.explorer_focus

    if name in focus do
      {:noreply, socket}
    else
      new_focus = focus ++ [name]
      socket = assign(socket, explorer_focus: new_focus, explorer_loading: true)
      send(self(), {:fetch_suggestions, new_focus})
      {:noreply, socket}
    end
  end

  def handle_event("deselect_table", %{"name" => name}, socket) do
    new_focus = List.delete(socket.assigns.explorer_focus, name)

    if new_focus == [] do
      {:noreply, assign(socket, explorer_focus: [], explorer_suggestions: [], explorer_loading: false)}
    else
      socket = assign(socket, explorer_focus: new_focus, explorer_loading: true)
      send(self(), {:fetch_suggestions, new_focus})
      {:noreply, socket}
    end
  end

  def handle_event("reset_explorer", _params, socket) do
    {:noreply,
     assign(socket,
       explorer_focus: [],
       explorer_suggestions: [],
       explorer_loading: false
     )}
  end

  def handle_event("run_suggestion", %{"text" => text}, socket) do
    run_query(text, socket)
  end

  def handle_event("edit_suggestion", %{"text" => text}, socket) do
    {:noreply, assign(socket, form: to_form(%{"prompt" => text}, as: :query))}
  end
```

Add handle_info for suggestion fetching:

```elixir
  def handle_info({:fetch_suggestions, table_names}, socket) do
    suggestions = SchemaExplorer.suggest(table_names)

    {:noreply,
     assign(socket,
       explorer_suggestions: suggestions,
       explorer_loading: false
     )}
  end
```

- [ ] **Step 6: Add `table_cells` icon to `Dai.Icons` if missing**

```elixir
  def table_cells(assigns) do
    assigns = assign_defaults(assigns)

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class={@class}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 0 1-1.125-1.125M3.375 19.5h7.5c.621 0 1.125-.504 1.125-1.125m-9.75 0V5.625m0 12.75v-1.5c0-.621.504-1.125 1.125-1.125m18.375 2.625V5.625m0 12.75c0 .621-.504 1.125-1.125 1.125m1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125m0 3.75h-7.5A1.125 1.125 0 0 1 12 18.375m9.75-12.75c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125m19.5 0v1.5c0 .621-.504 1.125-1.125 1.125M2.25 5.625v1.5c0 .621.504 1.125 1.125 1.125m0 0h17.25m-17.25 0h7.5c.621 0 1.125.504 1.125 1.125M3.375 8.25c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125m17.25-3.75h-7.5c-.621 0-1.125.504-1.125 1.125m8.625-1.125c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125M12 10.875v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 10.875c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125M10.875 12h-7.5m7.5 0c.621 0 1.125.504 1.125 1.125M12 12h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125m0 1.5v-1.5m0 0c0-.621.504-1.125 1.125-1.125m-1.125 2.625v1.5c0 .621.504 1.125 1.125 1.125M12 15.375h-7.5" />
    </svg>
    """
  end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `mix test test/dai_web/live/dashboard_live_test.exs`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/dai/schema_explorer_components.ex lib/dai/dashboard_live.ex lib/dai/icons.ex test/dai_web/live/dashboard_live_test.exs
git commit -m "feat(explorer): add schema panel drawer with click-to-explore flow"
```

---

### Task 6: Final integration tests and precommit

**Files:**
- Modify: `test/dai_web/live/dashboard_live_test.exs`

This task adds end-to-end interaction tests and runs the full precommit suite.

- [ ] **Step 1: Write interaction tests**

Add to `test/dai_web/live/dashboard_live_test.exs`:

```elixir
  describe "suggestion interaction" do
    test "run_suggestion executes a query", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # The run_suggestion event should set loading state
      render_hook(view, "run_suggestion", %{"text" => "How many users?"})
      assert has_element?(view, ".loading")
    end

    test "edit_suggestion fills the input without executing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "edit_suggestion", %{"text" => "Revenue by plan"})
      refute has_element?(view, ".loading")
    end
  end

  describe "schema panel and empty state coexistence" do
    test "schema button is always visible", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "button[phx-click=toggle_schema_panel]")
    end
  end
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `mix test test/dai_web/live/dashboard_live_test.exs`
Expected: All tests pass.

- [ ] **Step 3: Run the full precommit suite**

Run: `mix precommit`
Expected: All checks pass — compile warnings, unused deps, format, tests.

- [ ] **Step 4: Fix any issues found by precommit**

If `mix format` reports changes, run `mix format` and update files.
If compile warnings appear, fix them.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "test(explorer): add interaction tests, pass precommit"
```

---

## Summary

| Task | What it builds | Key files |
|---|---|---|
| 1 | SchemaExplorer GenServer with structured data + row counts | `schema_explorer.ex`, `application.ex` |
| 2 | Boot-time AI suggestion generation | `schema_explorer.ex` |
| 3 | On-demand suggestions with ETS cache | `schema_explorer.ex` |
| 4 | Empty state UI (stats, tables, suggestions) | `schema_explorer_components.ex`, `dashboard_live.ex` |
| 5 | Schema panel drawer (all tables, detail, multi-focus) | `schema_explorer_components.ex`, `dashboard_live.ex` |
| 6 | Integration tests + precommit | `dashboard_live_test.exs` |
