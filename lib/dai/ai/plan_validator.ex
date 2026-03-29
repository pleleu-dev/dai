defmodule Dai.AI.PlanValidator do
  @moduledoc "Validates the plan returned by the Claude API."

  alias Dai.AI.Component

  @forbidden_pattern ~r/\b(insert|update|delete|drop|truncate|alter|create|grant|revoke|exec|execute)\b/i

  def validate(%{"sql" => sql, "component" => component} = plan) do
    with :ok <- check_forbidden_keywords(sql),
         :ok <- check_component(component) do
      {:ok, ensure_limit(plan)}
    end
  end

  def validate(_plan), do: {:error, :invalid_plan}

  defp check_forbidden_keywords(sql) do
    if Regex.match?(@forbidden_pattern, sql) do
      {:error, :forbidden_sql}
    else
      :ok
    end
  end

  defp check_component(component) do
    if Component.valid?(component), do: :ok, else: {:error, :invalid_component}
  end

  defp ensure_limit(%{"sql" => sql, "component" => component} = plan) do
    if Regex.match?(~r/\bLIMIT\b/i, sql) do
      plan
    else
      %{
        plan
        | "sql" => "#{String.trim_trailing(sql)} LIMIT #{Component.default_limit(component)}"
      }
    end
  end
end
