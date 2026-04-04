defmodule Dai.AI.ActionExecutor do
  @moduledoc "Executes an action against one or more target rows."

  @spec execute_all(module(), [map()], map()) ::
          {:ok, [term()]} | {:partial, [term()], [{map(), term()}]} | {:error, term()}
  def execute_all(action_module, targets, params) do
    results =
      Enum.map(targets, fn target ->
        {target, action_module.execute(target, params)}
      end)

    successes = for {_t, {:ok, val}} <- results, do: val
    failures = for {t, {:error, reason}} <- results, do: {t, reason}

    case {successes, failures} do
      {_, []} -> {:ok, successes}
      {[], [{_t, reason} | _]} -> {:error, reason}
      {_, _} -> {:partial, successes, failures}
    end
  end
end
