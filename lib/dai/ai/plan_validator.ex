defmodule Dai.AI.PlanValidator do
  @moduledoc """
  Validates the plan returned by the Claude API.

  ## Security boundary

  The `@forbidden_pattern` keyword blocklist is **defense-in-depth, not the
  primary control**. A regex cannot reliably reject every dangerous construct —
  CTEs, `pg_`-prefixed functions (`pg_read_file`), `COPY ... PROGRAM`, and
  function-based exfiltration can be expressed in ways a keyword scan misses.
  The real boundary is the read-only execution layer in `Dai.AI.SqlExecutor`
  (`SET LOCAL transaction_read_only = on` + `statement_timeout`, ideally backed
  by a dedicated `:readonly_repo` role with only `GRANT SELECT`). The blocklist
  exists to fail obviously-malicious plans early with a clear error.
  """

  require Logger

  alias Dai.AI.{ActionRegistry, Component}

  @forbidden_pattern ~r/\b(insert|update|delete|drop|truncate|alter|create|grant|revoke|exec|execute|copy|vacuum|merge)\b/i
  @limit_clause ~r/\bLIMIT\s+(ALL|\d+)\b/i

  def validate(plan, scope \\ nil)

  def validate(%{"type" => "action", "sql" => sql, "action_id" => action_id} = plan, scope) do
    with :ok <- check_forbidden_keywords(sql),
         :ok <- check_action(action_id),
         :ok <- enforce_scope(sql, scope) do
      {:ok, plan}
    end
  end

  def validate(%{"sql" => sql, "component" => component} = plan, scope) do
    with :ok <- check_forbidden_keywords(sql),
         :ok <- check_component(component),
         validated = ensure_limit(plan),
         :ok <- enforce_scope(validated["sql"], scope) do
      {:ok, validated}
    end
  end

  def validate(_plan, _scope), do: {:error, :invalid_plan}

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

  # Best-effort tenant-scope enforcement (defense-in-depth). When a scope is
  # active (a scope map carrying a `:value` reached the pipeline), the generated
  # SQL must mention the scope column or the query is rejected — this fails closed
  # when the AI omits the filter entirely. It is a heuristic substring check and
  # CAN be fooled (the column name appearing in a comment or string literal), so
  # it is NOT a substitute for the real boundary: the `dai.scope_value` GUC
  # published in `Dai.AI.SqlExecutor` plus host-defined RLS policies.
  defp enforce_scope(_sql, nil), do: :ok

  defp enforce_scope(sql, scope) do
    case scope_column(scope) do
      nil ->
        :ok

      column ->
        if String.contains?(sql, column) do
          :ok
        else
          Logger.warning("Dai query blocked: SQL not scoped to tenant",
            column: column,
            sql: sql
          )

          {:error, :scope_violation}
        end
    end
  end

  defp scope_column(%{column: column}) when not is_nil(column), do: to_string(column)
  defp scope_column(_scope), do: nil

  # Clamps the query's row cap to the smaller of the component's default limit
  # and the global `Config.max_rows/0` ceiling. An existing `LIMIT n` is
  # rewritten down when it exceeds the ceiling (or is `LIMIT ALL`); a missing
  # LIMIT is appended. A small existing LIMIT is preserved.
  defp ensure_limit(%{"sql" => sql, "component" => component} = plan) do
    ceiling = min(Component.default_limit(component), Dai.Config.max_rows())
    %{plan | "sql" => clamp_limit(sql, ceiling)}
  end

  defp clamp_limit(sql, ceiling) do
    case Regex.run(@limit_clause, sql, capture: :all_but_first) do
      [value] ->
        if limit_within?(value, ceiling) do
          sql
        else
          Regex.replace(@limit_clause, sql, "LIMIT #{ceiling}", global: false)
        end

      nil ->
        "#{String.trim_trailing(sql)} LIMIT #{ceiling}"
    end
  end

  defp limit_within?(value, ceiling) do
    case Integer.parse(value) do
      {n, ""} -> n <= ceiling
      # "ALL" or any non-integer value → force clamp to the ceiling
      _ -> false
    end
  end
end
