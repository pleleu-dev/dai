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
    |> Task.async_stream(&build_table/1, timeout: 10_000, on_timeout: :kill_task)
    |> Enum.flat_map(fn
      {:ok, table} -> [table]
      {:exit, _reason} -> []
    end)
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

    case repo.query(~s[SELECT count(*) FROM "#{table_name}"]) do
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
