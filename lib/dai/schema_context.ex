defmodule Dai.SchemaContext do
  @moduledoc "Caches the AI schema context string in memory via :persistent_term."

  @key :dai_schema_context
  @json_path "priv/ai/schema_context.json"

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  def start_link(_opts) do
    :persistent_term.put(@key, load_context())
    :ignore
  end

  def get do
    :persistent_term.get(@key)
  end

  def reload do
    :persistent_term.put(@key, load_context())
    :ok
  end

  defp load_context do
    case File.read(@json_path) do
      {:ok, json} ->
        json |> Jason.decode!() |> format_context()

      {:error, _} ->
        "No schema context available. The schema context file has not been generated yet."
    end
  end

  defp format_context(tables) do
    Enum.map_join(tables, "\n\n", fn table ->
      fields = Enum.map_join(table["fields"], ", ", fn f -> "#{f["name"]} (#{f["type"]})" end)

      associations =
        case table["associations"] do
          [] ->
            ""

          assocs ->
            assoc_str =
              Enum.map_join(assocs, ", ", fn a ->
                "#{a["type"]} #{a["name"]} (#{a["related_table"]})"
              end)

            "\n  Associations: #{assoc_str}"
        end

      pk = Enum.join(table["primary_key"], ", ")

      "Table: #{table["table"]}\n  Primary key: #{pk}\n  Columns: #{fields}#{associations}"
    end)
  end
end
