defmodule Dai.AI.PlanValidator do
  @moduledoc "Validates the plan returned by the Claude API."

  require Logger

  alias Dai.AI.{ActionRegistry, Component}

  @forbidden_pattern ~r/\b(insert|update|delete|drop|truncate|alter|create|grant|revoke|exec|execute)\b/i

  def validate(%{"type" => "action", "sql" => sql, "action_id" => action_id} = plan) do
    with :ok <- check_forbidden_keywords(sql),
         :ok <- check_action(action_id) do
      warn_if_missing_scope(sql)
      {:ok, plan}
    end
  end

  def validate(%{"sql" => sql, "component" => component} = plan) do
    with :ok <- check_forbidden_keywords(sql),
         :ok <- check_component(component) do
      validated = ensure_limit(plan)
      warn_if_missing_scope(validated["sql"])
      {:ok, validated}
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

  defp check_action(action_id) do
    case ActionRegistry.lookup(action_id) do
      {:ok, _module} -> :ok
      :error -> {:error, :invalid_action}
    end
  end

  defp warn_if_missing_scope(sql) do
    case Dai.Config.query_scope() do
      %{column: column} ->
        unless String.contains?(sql, column) do
          Logger.warning("Dai query missing scope column: #{column}")
        end

      _ ->
        :ok
    end
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
