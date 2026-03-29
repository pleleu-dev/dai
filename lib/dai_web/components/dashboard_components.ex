defmodule DaiWeb.DashboardComponents do
  @moduledoc "Function components for dashboard result cards."

  use Phoenix.Component
  import DaiWeb.CoreComponents, only: [icon: 1]

  alias Dai.AI.Result

  attr :result, Result, required: true

  def result_card(assigns) do
    ~H"""
    <div
      id={"result-#{@result.id}"}
      class={[
        "rounded-lg border border-base-300 bg-base-100 shadow-sm overflow-hidden",
        @result.type == :error && "border-error/30"
      ]}
    >
      <div class="flex items-start justify-between p-4 pb-2">
        <div>
          <h3 class="font-semibold text-base-content text-sm">{@result.title}</h3>
          <p class="text-xs text-base-content/60 mt-0.5">{@result.description}</p>
        </div>
        <button
          phx-click="dismiss"
          phx-value-id={@result.id}
          class="btn btn-ghost btn-xs btn-circle opacity-50 hover:opacity-100"
          aria-label="Dismiss"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <div class="p-4 pt-2">
        <.card_body result={@result} />
      </div>
    </div>
    """
  end

  attr :result, Result, required: true

  defp card_body(%{result: %{type: :kpi_metric}} = assigns) do
    ~H"""
    <.kpi_metric result={@result} />
    """
  end

  defp card_body(%{result: %{type: type}} = assigns)
       when type in [:bar_chart, :line_chart, :pie_chart] do
    ~H"""
    <.chart result={@result} />
    """
  end

  defp card_body(%{result: %{type: :data_table}} = assigns) do
    ~H"""
    <.data_table result={@result} />
    """
  end

  defp card_body(%{result: %{type: :error}} = assigns) do
    ~H"""
    <.error_card result={@result} />
    """
  end

  defp card_body(%{result: %{type: :clarification}} = assigns) do
    ~H"""
    <.clarification_card result={@result} />
    """
  end

  attr :result, Result, required: true

  defp kpi_metric(assigns) do
    value = get_kpi_value(assigns.result)
    format = get_in(assigns.result.config, ["format"]) || "number"
    formatted = format_kpi(value, format)
    label = get_in(assigns.result.config, ["label"]) || assigns.result.title
    assigns = assign(assigns, formatted: formatted, label: label)

    ~H"""
    <div class="text-center py-4">
      <div class="text-4xl font-bold text-primary">{@formatted}</div>
      <div class="text-sm text-base-content/60 mt-1">{@label}</div>
    </div>
    """
  end

  attr :result, Result, required: true

  defp chart(assigns) do
    chart_type = chart_type_string(assigns.result.type)
    chart_config = build_chart_config(assigns.result)
    assigns = assign(assigns, chart_type: chart_type, chart_config: Jason.encode!(chart_config))

    ~H"""
    <div
      id={"chart-#{@result.id}"}
      phx-hook="ChartHook"
      phx-update="ignore"
      data-chart-type={@chart_type}
      data-chart-config={@chart_config}
      class="relative h-64"
    >
      <canvas></canvas>
    </div>
    """
  end

  attr :result, Result, required: true

  defp data_table(assigns) do
    columns = assigns.result.data.columns
    rows = assigns.result.data.rows
    assigns = assign(assigns, columns: columns, rows: rows)

    ~H"""
    <div class="overflow-x-auto max-h-80">
      <table class="table table-xs">
        <thead>
          <tr>
            <th :for={col <- @columns} class="text-base-content/70">{col}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class="hover:bg-base-200/50">
            <td :for={col <- @columns} class="text-sm">{format_cell(row[col])}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :result, Result, required: true

  defp error_card(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-3 py-4">
      <div class="flex items-center gap-2 text-error">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span class="text-sm">{@result.error}</span>
      </div>
      <button
        phx-click="retry"
        phx-value-prompt={@result.prompt}
        class="btn btn-sm btn-outline btn-error"
      >
        Try again
      </button>
    </div>
    """
  end

  attr :result, Result, required: true

  defp clarification_card(assigns) do
    ~H"""
    <div class="flex flex-col gap-3 py-2">
      <div class="flex items-start gap-2">
        <.icon name="hero-chat-bubble-left-ellipsis" class="size-5 text-info shrink-0 mt-0.5" />
        <p class="text-sm text-base-content">{@result.question}</p>
      </div>
      <form phx-submit="query" class="flex gap-2">
        <input
          type="text"
          name="prompt"
          placeholder="Type your answer..."
          class="input input-sm input-bordered flex-1"
          autocomplete="off"
        />
        <button type="submit" class="btn btn-sm btn-primary">Send</button>
      </form>
    </div>
    """
  end

  # --- Helpers ---

  defp get_kpi_value(%{data: %{rows: [first | _], columns: [col | _]}}) do
    Map.get(first, col)
  end

  defp get_kpi_value(_), do: 0

  defp format_kpi(value, "currency") when is_integer(value) do
    "$#{format_integer(value)}.00"
  end

  defp format_kpi(value, "currency") when is_float(value) do
    "$#{:erlang.float_to_binary(value, decimals: 2)}"
  end

  defp format_kpi(value, "currency"), do: "$#{value}"

  defp format_kpi(value, "percent") when is_float(value) do
    "#{:erlang.float_to_binary(value, decimals: 1)}%"
  end

  defp format_kpi(value, "percent") when is_integer(value), do: "#{value}%"

  defp format_kpi(value, _format) when is_integer(value), do: format_integer(value)
  defp format_kpi(value, _format), do: to_string(value)

  defp format_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_cell(nil), do: "-"
  defp format_cell(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_cell(%Date{} = d), do: Calendar.strftime(d, "%Y-%m-%d")
  defp format_cell(value), do: to_string(value)

  defp chart_type_string(:bar_chart), do: "bar"
  defp chart_type_string(:line_chart), do: "line"
  defp chart_type_string(:pie_chart), do: "pie"

  defp build_chart_config(%{type: :pie_chart, data: data, config: config}) do
    label_field = config["label_field"] || Enum.at(data.columns, 0)
    value_field = config["value_field"] || Enum.at(data.columns, 1)

    labels = Enum.map(data.rows, &to_string(&1[label_field]))
    values = Enum.map(data.rows, & &1[value_field])
    cutout = if length(labels) > 4, do: "50%", else: nil

    %{labels: labels, values: values, cutout: cutout}
  end

  defp build_chart_config(%{data: data, config: config}) do
    x_axis = config["x_axis"] || Enum.at(data.columns, 0)
    y_axis = config["y_axis"] || Enum.at(data.columns, 1)

    labels = Enum.map(data.rows, &to_string(&1[x_axis]))
    values = Enum.map(data.rows, & &1[y_axis])
    fill = config["fill"] || false

    %{labels: labels, values: values, fill: fill, dataset_label: config["y_axis"] || ""}
  end
end
