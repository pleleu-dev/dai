defmodule Dai.AI.Client do
  @moduledoc "Sends prompts to the Claude API via Req and parses JSON responses."

  @api_url "https://api.anthropic.com/v1/messages"

  def generate_plan(prompt, schema_context) do
    config = Application.get_env(:dai, :ai, [])

    with {:ok, api_key} <- fetch_api_key(config) do
      body = build_request_body(prompt, schema_context, config)
      call_api(api_key, body)
    end
  end

  defp fetch_api_key(config) do
    case Keyword.get(config, :api_key) do
      nil -> {:error, :api_error}
      key -> {:ok, key}
    end
  end

  defp build_request_body(prompt, schema_context, config) do
    %{
      model: Keyword.get(config, :model, "claude-sonnet-4-6"),
      max_tokens: Keyword.get(config, :max_tokens, 1024),
      system: Dai.AI.SystemPrompt.build(schema_context),
      messages: [%{role: "user", content: prompt}]
    }
  end

  defp call_api(api_key, body) do
    case Req.post(@api_url,
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"},
             {"content-type", "application/json"}
           ],
           receive_timeout: 30_000
         ) do
      {:ok, %Req.Response{status: 200, body: resp_body}} -> parse_response(resp_body)
      _ -> {:error, :api_error}
    end
  end

  defp parse_response(%{"content" => [%{"text" => text} | _]}) do
    case Jason.decode(text) do
      {:ok, plan} when is_map(plan) -> {:ok, plan}
      _ -> {:error, :invalid_json}
    end
  end

  defp parse_response(_), do: {:error, :invalid_json}
end
