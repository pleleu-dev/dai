defmodule Dai.SchemaExplorer do
  @moduledoc "Enriches schema context with row counts and AI-generated suggestions."

  alias Dai.AI.Client
  alias Dai.Schema.Discovery

  @key :dai_schema_explorer

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  def start_link(_opts) do
    if :ets.whereis(:dai_explorer_cache) == :undefined do
      :ets.new(:dai_explorer_cache, [:set, :public, :named_table])
    end

    data = build_explorer_data()
    :persistent_term.put(@key, data)
    :ignore
  end

  @doc "Returns cached schema explorer data."
  def get do
    :persistent_term.get(@key, %{
      tables: [],
      suggestions: [],
      total_columns: 0,
      total_relationships: 0
    })
  end

  @doc "Rebuilds and recaches schema explorer data."
  def reload do
    if :ets.whereis(:dai_explorer_cache) != :undefined do
      :ets.delete_all_objects(:dai_explorer_cache)
    end

    :persistent_term.put(@key, build_explorer_data())
    :ok
  end

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

  # --- Data building ---

  defp build_explorer_data do
    schemas = Discovery.discover_schemas()
    tables = build_tables(schemas)
    schema_context = Dai.SchemaContext.get()
    suggestions = generate_boot_suggestions(schema_context)

    %{
      tables: tables,
      suggestions: suggestions,
      total_columns: tables |> Enum.flat_map(& &1.columns) |> length(),
      total_relationships: tables |> Enum.flat_map(& &1.associations) |> length()
    }
  end

  defp build_tables(schemas) do
    schemas
    |> Task.async_stream(&build_table/1, timeout: 10_000, on_timeout: :kill_task)
    |> Enum.flat_map(fn
      {:ok, table} -> [table]
      {:exit, _reason} -> []
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp build_table(mod) do
    source = mod.__schema__(:source)
    columns = extract_columns(mod)
    associations = extract_associations(mod)

    %{
      name: source,
      columns: columns,
      column_count: length(columns),
      primary_key: mod.__schema__(:primary_key),
      associations: associations,
      association_count: length(associations),
      row_count: query_row_count(source)
    }
  end

  defp extract_columns(mod) do
    mod.__schema__(:fields)
    |> Enum.map(fn field ->
      type = mod.__schema__(:type, field)
      %{name: Atom.to_string(field), type: Discovery.format_type(type)}
    end)
  end

  defp extract_associations(mod) do
    mod.__schema__(:associations)
    |> Enum.map(fn assoc_name ->
      assoc = mod.__schema__(:association, assoc_name)

      %{
        type: Discovery.assoc_type(assoc),
        name: assoc_name,
        target: assoc.queryable.__schema__(:source)
      }
    end)
  end

  defp query_row_count(table_name) do
    repo = Dai.Config.repo()

    case repo.query(~s[SELECT count(*) FROM "#{table_name}"]) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end

  # --- Suggestion generation ---

  defp generate_boot_suggestions(schema_context) do
    prompt = """
    Given this database schema:

    #{schema_context}

    Generate 5-8 example questions that a non-technical user would find useful for exploring this data.
    Prefer questions that span multiple tables (JOINs).
    Return ONLY a valid JSON array, no other text:
    [{"text": "human-readable question", "tables": ["table1", "table2"]}]
    """

    case call_suggestion_api(prompt) do
      {:ok, suggestions} -> suggestions
      {:error, _} -> []
    end
  end

  defp generate_on_demand_suggestions(table_names) do
    %{tables: all_tables, suggestions: boot_suggestions} = get()
    matching_boot = filter_matching_boot(boot_suggestions, table_names)

    case generate_suggestions_for_tables(all_tables, table_names) do
      {:ok, ai_suggestions} -> merge_suggestions(ai_suggestions, matching_boot)
      {:error, _} -> matching_boot
    end
  end

  defp filter_matching_boot(boot_suggestions, table_names) do
    Enum.filter(boot_suggestions, fn s ->
      Enum.any?(s.tables, &(&1 in table_names))
    end)
  end

  defp generate_suggestions_for_tables(all_tables, table_names) do
    selected_schemas =
      all_tables
      |> Enum.filter(&(&1.name in table_names))
      |> Enum.map_join("\n\n", &format_table_for_prompt/1)

    focus_hint =
      if length(table_names) == 1,
        do: "Focus on useful queries for this single table.",
        else: "Focus on queries that combine these tables."

    prompt = """
    Given these database tables:

    #{selected_schemas}

    Generate 3-5 example questions a non-technical user would ask about this data.
    #{focus_hint}
    Return ONLY a valid JSON array, no other text:
    [{"text": "human-readable question", "tables": ["table1", "table2"]}]
    """

    call_suggestion_api(prompt)
  end

  defp merge_suggestions(ai_suggestions, boot_suggestions) do
    seen = MapSet.new(ai_suggestions, & &1.text)
    unique_boot = Enum.reject(boot_suggestions, &MapSet.member?(seen, &1.text))
    ai_suggestions ++ unique_boot
  end

  defp format_table_for_prompt(table) do
    cols = Enum.map_join(table.columns, ", ", &"#{&1.name} (#{&1.type})")
    assocs = Enum.map_join(table.associations, ", ", &"#{&1.type} #{&1.name} (#{&1.target})")

    assoc_line = if assocs != "", do: "\n  Associations: #{assocs}", else: ""
    "Table: #{table.name}\n  Columns: #{cols}#{assoc_line}"
  end

  defp call_suggestion_api(prompt) do
    case Client.send_messages([%{role: "user", content: prompt}]) do
      {:ok, list} when is_list(list) -> {:ok, parse_suggestions(list)}
      {:ok, _} -> {:error, :invalid_format}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_suggestions(list) do
    list
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn item ->
      %{
        text: Map.get(item, "text", ""),
        tables: Map.get(item, "tables", [])
      }
    end)
  end

  # --- ETS cache ---

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
end
