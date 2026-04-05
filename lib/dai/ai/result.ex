defmodule Dai.AI.Result do
  @moduledoc "Represents a query result card in the dashboard grid."

  @type t :: %__MODULE__{
          id: String.t(),
          type:
            :kpi_metric
            | :bar_chart
            | :line_chart
            | :pie_chart
            | :data_table
            | :clarification
            | :error
            | :action_confirmation
            | :action_result,
          title: String.t() | nil,
          description: String.t() | nil,
          config: map() | nil,
          data: %{columns: [String.t()], rows: [map()]} | nil,
          prompt: String.t(),
          error: String.t() | nil,
          question: String.t() | nil,
          action_id: String.t() | nil,
          action_targets: [map()] | nil,
          action_params: map() | nil,
          timestamp: DateTime.t(),
          layout_key: String.t() | nil
        }

  @enforce_keys [:id, :type, :prompt, :timestamp]
  defstruct [
    :id,
    :type,
    :title,
    :description,
    :config,
    :data,
    :prompt,
    :error,
    :question,
    :action_id,
    :action_targets,
    :action_params,
    :timestamp,
    :layout_key
  ]

  def generate_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end

  def error(reason, prompt) do
    message = error_message(reason)

    %__MODULE__{
      id: generate_id(),
      type: :error,
      title: "Error",
      description: message,
      error: message,
      prompt: prompt,
      timestamp: DateTime.utc_now()
    }
  end

  defp error_message(:api_error), do: "Could not reach the AI service. Please try again."

  defp error_message(:invalid_json),
    do: "The AI returned an unexpected response. Please try again."

  defp error_message(:forbidden_sql),
    do: "The generated query contained forbidden operations and was blocked."

  defp error_message(:invalid_component), do: "The AI suggested an unknown visualization type."
  defp error_message(:invalid_action), do: "The AI suggested an unknown action."
  defp error_message({:query_failed, detail}), do: "The database query failed: #{detail}"
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: "An unexpected error occurred: #{inspect(reason)}"
end
