defmodule Dai.AI.Component do
  @moduledoc "Canonical definition of visualization component types."

  @typedoc "The canonical set of visualization component atoms."
  @type component_type :: :kpi_metric | :bar_chart | :line_chart | :pie_chart | :data_table

  @types %{
    "kpi_metric" => %{atom: :kpi_metric, chart?: false, default_limit: 50},
    "bar_chart" => %{atom: :bar_chart, chart?: true, default_limit: 50},
    "line_chart" => %{atom: :line_chart, chart?: true, default_limit: 50},
    "pie_chart" => %{atom: :pie_chart, chart?: true, default_limit: 50},
    "data_table" => %{atom: :data_table, chart?: false, default_limit: 500}
  }

  def valid?(name), do: Map.has_key?(@types, name)
  def to_atom(name), do: @types[name].atom
  def default_limit(name), do: @types[name].default_limit
end
