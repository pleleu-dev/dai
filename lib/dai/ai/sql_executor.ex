defmodule Dai.AI.SqlExecutor do
  @moduledoc "Executes validated SQL against the database."

  def execute(%{"sql" => sql}) do
    case Ecto.Adapters.SQL.query(Dai.Config.repo(), sql) do
      {:ok, %Postgrex.Result{columns: columns, rows: rows}} ->
        mapped_rows =
          Enum.map(rows, fn row ->
            columns
            |> Enum.zip(row)
            |> Map.new(fn {col, val} -> {col, normalize_value(val)} end)
          end)

        {:ok, %{columns: columns, rows: mapped_rows}}

      {:error, %Postgrex.Error{postgres: %{message: message}}} ->
        {:error, {:query_failed, message}}

      {:error, error} ->
        {:error, {:query_failed, inspect(error)}}
    end
  end

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
