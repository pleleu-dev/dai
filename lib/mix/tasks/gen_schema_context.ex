defmodule Mix.Tasks.GenSchemaContext do
  @moduledoc "Introspects Ecto schemas and writes schema context JSON to priv/ai/schema_context.json"
  @shortdoc "Generate AI schema context JSON"

  use Mix.Task

  @output_path "priv/ai/schema_context.json"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")

    schemas = discover_schemas()
    context = Enum.map(schemas, &extract_schema_info/1)

    File.mkdir_p!(Path.dirname(@output_path))
    File.write!(@output_path, Jason.encode!(context, pretty: true))

    Mix.shell().info("Wrote schema context for #{length(context)} tables to #{@output_path}")
  end

  defp discover_schemas do
    {:ok, modules} = :application.get_key(:dai, :modules)

    Enum.filter(modules, fn mod ->
      Code.ensure_loaded?(mod) and function_exported?(mod, :__schema__, 1)
    end)
  end

  defp extract_schema_info(mod) do
    source = mod.__schema__(:source)
    fields = mod.__schema__(:fields)
    primary_key = mod.__schema__(:primary_key)

    field_info =
      Enum.map(fields, fn field ->
        type = mod.__schema__(:type, field)
        %{name: Atom.to_string(field), type: format_type(type)}
      end)

    associations =
      mod.__schema__(:associations)
      |> Enum.map(fn assoc_name ->
        assoc = mod.__schema__(:association, assoc_name)

        %{
          name: Atom.to_string(assoc_name),
          type: assoc_type(assoc),
          related_table: assoc.queryable.__schema__(:source)
        }
      end)

    %{
      table: source,
      module: inspect(mod),
      primary_key: Enum.map(primary_key, &Atom.to_string/1),
      fields: field_info,
      associations: associations
    }
  end

  defp assoc_type(%Ecto.Association.BelongsTo{}), do: "belongs_to"
  defp assoc_type(%Ecto.Association.Has{cardinality: :many}), do: "has_many"
  defp assoc_type(%Ecto.Association.Has{cardinality: :one}), do: "has_one"
  defp assoc_type(%Ecto.Association.ManyToMany{}), do: "many_to_many"
  defp assoc_type(_), do: "unknown"

  defp format_type({:parameterized, {Ecto.Embedded, _}}), do: "embedded"
  defp format_type(type) when is_atom(type), do: Atom.to_string(type)
  defp format_type(type), do: inspect(type)
end
