defmodule Dai.SchemaContext do
  @moduledoc "Discovers Ecto schemas at boot and caches a formatted context string."

  @key :dai_schema_context

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  def start_link(_opts) do
    :persistent_term.put(@key, build_context())
    :ignore
  end

  def get do
    :persistent_term.get(@key)
  end

  def reload do
    :persistent_term.put(@key, build_context())
    :ok
  end

  defp build_context do
    schemas = discover_schemas()

    if schemas == [] do
      "No schemas discovered. Check your :dai :schema_contexts configuration."
    else
      schemas
      |> Enum.map(&extract_schema_info/1)
      |> Enum.join("\n\n")
    end
  end

  defp discover_schemas do
    contexts = Dai.Config.schema_contexts()
    extras = Dai.Config.extra_schemas()

    {:ok, modules} = :application.get_key(:dai, :modules)

    Enum.filter(modules, fn mod ->
      Code.ensure_loaded?(mod) and
        function_exported?(mod, :__schema__, 1) and
        (matches_context?(mod, contexts) or mod in extras)
    end)
  end

  defp matches_context?(_mod, []), do: true

  defp matches_context?(mod, contexts) do
    mod_string = Atom.to_string(mod)

    Enum.any?(contexts, fn ctx ->
      String.starts_with?(mod_string, Atom.to_string(ctx))
    end)
  end

  defp extract_schema_info(mod) do
    fields =
      mod.__schema__(:fields)
      |> Enum.map(fn field ->
        type = mod.__schema__(:type, field)
        "#{field} (#{format_type(type)})"
      end)
      |> Enum.join(", ")

    associations =
      mod.__schema__(:associations)
      |> Enum.map(fn assoc_name ->
        assoc = mod.__schema__(:association, assoc_name)
        "#{assoc_type(assoc)} #{assoc_name} (#{assoc.queryable.__schema__(:source)})"
      end)

    pk = mod.__schema__(:primary_key) |> Enum.join(", ")
    source = mod.__schema__(:source)

    assoc_str =
      case associations do
        [] -> ""
        list -> "\n  Associations: #{Enum.join(list, ", ")}"
      end

    "Table: #{source}\n  Primary key: #{pk}\n  Columns: #{fields}#{assoc_str}"
  end

  defp assoc_type(%Ecto.Association.BelongsTo{}), do: "belongs_to"
  defp assoc_type(%Ecto.Association.Has{cardinality: :many}), do: "has_many"
  defp assoc_type(%Ecto.Association.Has{cardinality: :one}), do: "has_one"
  defp assoc_type(%Ecto.Association.ManyToMany{}), do: "many_to_many"
  defp assoc_type(_), do: "unknown"

  defp format_type(type) when is_atom(type), do: Atom.to_string(type)
  defp format_type({:parameterized, {Ecto.Embedded, _}}), do: "embedded"
  defp format_type(type), do: inspect(type)
end
