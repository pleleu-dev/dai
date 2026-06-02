defmodule Dai.AI.SqlExecutor do
  @moduledoc """
  Executes validated AI-generated SQL inside a read-only transaction.

  Every query runs through `Dai.Config.sql_repo/0` wrapped in a transaction that
  sets (via `SET LOCAL`, scoped to the transaction):

    * `transaction_read_only = on` — the engine rejects any write, so a plan
      that slips past `Dai.AI.PlanValidator` still cannot mutate data.
    * `statement_timeout` — bounds runaway queries (`Dai.Config.statement_timeout_ms/0`).

  A dedicated read-only Postgres role wired to `Dai.Config.readonly_repo/0`
  remains the recommended production boundary; this transaction is the always-on
  fallback when no such repo is configured.

  `SET LOCAL transaction_read_only = on` is used rather than
  `SET TRANSACTION READ ONLY` because the latter must be the first statement in a
  transaction, which is incompatible with the Ecto SQL sandbox (and harmless to
  avoid in production).
  """

  require Logger

  def execute(plan, scope \\ nil)

  def execute(%{"sql" => sql}, scope) do
    repo = Dai.Config.sql_repo()
    timeout = Dai.Config.statement_timeout_ms()

    outcome =
      repo.transaction(
        fn ->
          # statement_timeout is an integer from config (not user input) and
          # `SET` cannot take bind parameters, so interpolation is safe here.
          repo.query!("SET LOCAL transaction_read_only = on")
          repo.query!("SET LOCAL statement_timeout = #{timeout}")
          maybe_set_scope_guc(repo, scope)

          case repo.query(sql) do
            {:ok, result} -> result
            {:error, error} -> repo.rollback({:query_failed, postgres_message(error)})
          end
        end,
        timeout: timeout + 1_000
      )

    case outcome do
      {:ok, %Postgrex.Result{columns: columns, rows: rows}} ->
        {:ok, %{columns: columns, rows: normalize_rows(columns, rows)}}

      {:error, {:query_failed, detail} = reason} ->
        # Log the real Postgres detail here, at the trust boundary; the client
        # only ever sees the generic message from `Dai.AI.Result`.
        Logger.warning("Dai SQL execution failed", detail: detail)
        {:error, reason}

      {:error, reason} ->
        Logger.warning("Dai SQL transaction failed", detail: inspect(reason))
        {:error, {:query_failed, inspect(reason)}}
    end
  end

  # Publishes the tenant scope value as a transaction-local GUC so host RLS
  # policies can reference `current_setting('dai.scope_value', true)`. Uses
  # `set_config/3` (is_local = true) because `SET` cannot take bind parameters —
  # the value is passed as `$1`, never interpolated, so it can't inject SQL.
  defp maybe_set_scope_guc(repo, %{value: value}) when not is_nil(value) do
    repo.query!("SELECT set_config('dai.scope_value', $1, true)", [to_string(value)])
  end

  defp maybe_set_scope_guc(_repo, _scope), do: :ok

  defp normalize_rows(columns, rows) do
    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new(fn {col, val} -> {col, normalize_value(val)} end)
    end)
  end

  defp postgres_message(%Postgrex.Error{postgres: %{message: message}}), do: message
  defp postgres_message(error), do: inspect(error)

  defp normalize_value(%Decimal{} = d), do: Decimal.to_float(d)
  defp normalize_value(%Date{} = d), do: Date.to_iso8601(d)
  defp normalize_value(%Time{} = t), do: Time.to_iso8601(t)
  defp normalize_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp normalize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp normalize_value(<<a::4-bytes, b::2-bytes, c::2-bytes, d::2-bytes, e::6-bytes>>),
    do:
      Base.encode16(a, case: :lower) <>
        "-" <>
        Base.encode16(b, case: :lower) <>
        "-" <>
        Base.encode16(c, case: :lower) <>
        "-" <>
        Base.encode16(d, case: :lower) <>
        "-" <>
        Base.encode16(e, case: :lower)

  defp normalize_value(val), do: val
end
