defmodule Dai.DashboardComponents do
  @moduledoc "Function components for dashboard result cards."

  use Phoenix.Component

  alias Dai.AI.Result
  alias Dai.Icons

  attr :result, Result, required: true
  attr :folders, :list, default: []

  def result_card(assigns) do
    ~H"""
    <div
      id={"result-#{@result.id}"}
      class={[
        "card card-border card-compact bg-base-100",
        @result.type == :error && "border-error/30"
      ]}
    >
      <div class="card-body">
        <div class="flex items-start justify-between">
          <div class="min-w-0 flex-1">
            <h2 class="card-title text-sm">{@result.title}</h2>
            <p class="text-xs text-base-content/60">{@result.description}</p>
          </div>
          <div class="flex items-center gap-0.5 shrink-0">
            <Dai.SidebarComponents.save_button
              :if={@result.type not in [:error, :clarification, :action_confirmation, :action_result]}
              result_id={@result.id}
              prompt={@result.prompt}
              title={@result.title}
              folders={@folders}
            />
            <button
              phx-click="dismiss"
              phx-value-id={@result.id}
              class="btn btn-ghost btn-xs btn-circle opacity-50 hover:opacity-100"
              aria-label="Dismiss"
            >
              <Icons.x_mark class="size-4" />
            </button>
          </div>
        </div>
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

  defp card_body(%{result: %{type: :action_confirmation}} = assigns) do
    ~H"""
    <.action_confirmation_card result={@result} />
    """
  end

  defp card_body(%{result: %{type: :action_result}} = assigns) do
    ~H"""
    <.action_result_card result={@result} />
    """
  end

  # --- Card type components ---

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
        <Icons.exclamation_triangle class="size-5" />
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
        <Icons.chat_bubble class="size-5 text-info shrink-0 mt-0.5" />
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

  attr :result, Result, required: true

  defp action_confirmation_card(assigns) do
    targets = assigns.result.action_targets || []

    confirm_messages =
      case Dai.AI.ActionRegistry.lookup(assigns.result.action_id) do
        {:ok, action_module} -> Enum.map(targets, &action_module.confirm_message/1)
        :error -> Enum.map(targets, fn _ -> "Confirm action on this target?" end)
      end

    columns =
      case assigns.result.data do
        %{columns: columns} -> columns
        _ -> []
      end

    assigns =
      assign(assigns,
        targets: targets,
        columns: columns,
        confirm_messages: confirm_messages
      )

    ~H"""
    <div class="flex flex-col gap-3 py-2">
      <div class="overflow-x-auto max-h-48">
        <table class="table table-xs">
          <thead>
            <tr>
              <th :for={col <- @columns} class="text-base-content/70">{col}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @targets} class="hover:bg-base-200/50">
              <td :for={col <- @columns} class="text-sm">{format_cell(row[col])}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div
        :for={msg <- @confirm_messages}
        class="flex items-center gap-2 text-sm text-base-content/80"
      >
        <Icons.exclamation_triangle class="size-4 text-warning shrink-0" />
        <span>{msg}</span>
      </div>
      <div class="flex gap-2 justify-end">
        <button
          phx-click="dismiss"
          phx-value-id={@result.id}
          class="btn btn-ghost btn-sm"
        >
          Cancel
        </button>
        <button
          phx-click="confirm_action"
          phx-value-result-id={@result.id}
          class="btn btn-primary btn-sm"
        >
          Confirm
        </button>
      </div>
    </div>
    """
  end

  attr :result, Result, required: true

  defp action_result_card(assigns) do
    success = assigns.result.error == nil
    assigns = assign(assigns, success: success)

    ~H"""
    <div class={[
      "flex flex-col items-center gap-3 py-4",
      @success && "text-success",
      !@success && "text-error"
    ]}>
      <div class="flex items-center gap-2">
        <Icons.check :if={@success} class="size-5" />
        <Icons.exclamation_triangle :if={!@success} class="size-5" />
        <span class="text-sm">{@result.description}</span>
      </div>
    </div>
    """
  end

  # --- Chart builders ---

  defp build_live_chart(%{type: :bar_chart, data: data, config: config}) do
    {labels, values, y_name} = extract_axes(data, config)

    LiveCharts.build(%{
      type: :bar,
      series: [%{name: y_name, data: values}],
      options: %{xaxis: %{categories: labels}, chart: %{height: "100%"}}
    })
  end

  defp build_live_chart(%{type: :line_chart, data: data, config: config}) do
    {labels, values, y_name} = extract_axes(data, config)

    LiveCharts.build(%{
      type: :line,
      series: [%{name: y_name, data: values}],
      options: %{
        xaxis: %{categories: labels},
        chart: %{height: "100%"},
        stroke: %{curve: "smooth"}
      }
    })
  end

  defp build_live_chart(%{type: :pie_chart, data: data, config: config}) do
    label_field = config["label_field"] || Enum.at(data.columns, 0)
    value_field = config["value_field"] || Enum.at(data.columns, 1)
    labels = Enum.map(data.rows, &to_string(&1[label_field]))
    values = Enum.map(data.rows, & &1[value_field])

    LiveCharts.build(%{
      type: if(length(data.rows) > 4, do: :donut, else: :pie),
      series: values,
      options: %{labels: labels, chart: %{height: "100%"}}
    })
  end

  defp extract_axes(data, config) do
    x = config["x_axis"] || Enum.at(data.columns, 0)
    y = config["y_axis"] || Enum.at(data.columns, 1)
    labels = Enum.map(data.rows, &to_string(&1[x]))
    values = Enum.map(data.rows, & &1[y])
    {labels, values, y}
  end

  # --- Formatting helpers ---

  defp get_kpi_value(%{data: %{rows: [first | _], columns: [col | _]}}), do: Map.get(first, col)
  defp get_kpi_value(_), do: 0

  defp format_kpi(value, "currency") when is_integer(value), do: "$#{format_integer(value)}.00"

  defp format_kpi(value, "currency") when is_float(value),
    do: "$#{:erlang.float_to_binary(value, decimals: 2)}"

  defp format_kpi(value, "currency"), do: "$#{value}"

  defp format_kpi(value, "percent") when is_float(value),
    do: "#{:erlang.float_to_binary(value, decimals: 1)}%"

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
