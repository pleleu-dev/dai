defmodule Dai.DashboardComponents do
  @moduledoc "Function components for dashboard result cards."

  use Phoenix.Component

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
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4">
            <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
          </svg>
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
    chart = build_live_chart(assigns.result)
    assigns = assign(assigns, :chart, chart)

    ~H"""
    <div id={"chart-#{@result.id}"} class="h-64">
      <LiveCharts.chart chart={@chart} />
    </div>
    """
  end

  defp build_live_chart(%{type: :bar_chart, data: data, config: config}) do
    x_axis = config["x_axis"] || Enum.at(data.columns, 0)
    y_axis = config["y_axis"] || Enum.at(data.columns, 1)

    LiveCharts.build(%{
      type: :bar,
      series: [%{name: y_axis, data: Enum.map(data.rows, &(&1[y_axis]))}],
      options: %{
        xaxis: %{categories: Enum.map(data.rows, &to_string(&1[x_axis]))},
        chart: %{height: "100%"}
      }
    })
  end

  defp build_live_chart(%{type: :line_chart, data: data, config: config}) do
    x_axis = config["x_axis"] || Enum.at(data.columns, 0)
    y_axis = config["y_axis"] || Enum.at(data.columns, 1)

    LiveCharts.build(%{
      type: :line,
      series: [%{name: y_axis, data: Enum.map(data.rows, &(&1[y_axis]))}],
      options: %{
        xaxis: %{categories: Enum.map(data.rows, &to_string(&1[x_axis]))},
        chart: %{height: "100%"},
        stroke: %{curve: "smooth"}
      }
    })
  end

  defp build_live_chart(%{type: :pie_chart, data: data, config: config}) do
    label_field = config["label_field"] || Enum.at(data.columns, 0)
    value_field = config["value_field"] || Enum.at(data.columns, 1)

    LiveCharts.build(%{
      type: if(length(data.rows) > 4, do: :donut, else: :pie),
      series: Enum.map(data.rows, &(&1[value_field])),
      options: %{
        labels: Enum.map(data.rows, &to_string(&1[label_field])),
        chart: %{height: "100%"}
      }
    })
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
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-5">
          <path fill-rule="evenodd" d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495ZM10 5a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 10 5Zm0 9a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" clip-rule="evenodd" />
        </svg>
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
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-5 text-info shrink-0 mt-0.5">
          <path fill-rule="evenodd" d="M10 2c-2.236 0-4.43.18-6.57.524C1.993 2.755 1 4.014 1 5.426v5.148c0 1.413.993 2.67 2.43 2.902 1.168.188 2.352.327 3.55.414.28.02.521.18.642.413l1.713 3.293a.75.75 0 0 0 1.33 0l1.713-3.293a.783.783 0 0 1 .642-.413 41.102 41.102 0 0 0 3.55-.414c1.437-.231 2.43-1.49 2.43-2.902V5.426c0-1.413-.993-2.67-2.43-2.902A41.289 41.289 0 0 0 10 2ZM6.75 6a.75.75 0 0 0 0 1.5h6.5a.75.75 0 0 0 0-1.5h-6.5Zm0 2.5a.75.75 0 0 0 0 1.5h3.5a.75.75 0 0 0 0-1.5h-3.5Z" clip-rule="evenodd" />
        </svg>
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
end
