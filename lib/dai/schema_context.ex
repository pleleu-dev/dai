defmodule Dai.SchemaContext do
  @moduledoc "Discovers Ecto schemas at boot and caches a formatted context string."

  alias Dai.Schema.Discovery

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
    schemas = Discovery.discover_schemas()

    if schemas == [] do
      "No schemas discovered. Check your :dai :schema_contexts configuration."
    else
      schemas
      |> Enum.map(&extract_schema_info/1)
      |> Enum.join("\n\n")
    end
  end

  defp extract_schema_info(mod) do
    fields =
      mod.__schema__(:fields)
      |> Enum.map(fn field ->
        type = mod.__schema__(:type, field)
        "#{field} (#{Discovery.format_type(type)})"
      end)
      |> Enum.join(", ")

    associations =
      mod.__schema__(:associations)
      |> Enum.map(fn assoc_name ->
        assoc = mod.__schema__(:association, assoc_name)
        "#{Discovery.assoc_type(assoc)} #{assoc_name} (#{assoc.queryable.__schema__(:source)})"
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
end
