defmodule Dai.AI.ActionRegistry do
  @moduledoc "Reads configured action modules and provides lookup and prompt generation."

  @spec all() :: [map()]
  def all do
    Enum.map(Dai.Config.actions(), fn module ->
      %{
        id: module.id(),
        label: module.label(),
        description: module.description(),
        target_table: module.target_table(),
        target_key: module.target_key(),
        module: module
      }
    end)
  end

  @spec lookup(String.t()) :: {:ok, module()} | :error
  def lookup(action_id) do
    case Enum.find(Dai.Config.actions(), fn mod -> mod.id() == action_id end) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  @spec lookup!(String.t()) :: module()
  def lookup!(action_id) do
    case lookup(action_id) do
      {:ok, module} -> module
      :error -> raise ArgumentError, "Unknown action: #{action_id}"
    end
  end

  @spec prompt_section() :: String.t()
  def prompt_section do
    case Dai.Config.actions() do
      [] -> ""
      modules -> build_prompt_section(modules)
    end
  end

  defp build_prompt_section(modules) do
    action_lines =
      Enum.map_join(modules, "\n", fn mod ->
        "- #{mod.id()}: #{mod.label()}. #{mod.description()}. Target: #{mod.target_table()} (key: #{mod.target_key()})"
      end)

    """
    ## Available Actions

    When the user asks you to perform an action (not just view data), return an action plan instead of a query plan.

    Actions:
    #{action_lines}

    Action response format:
    {"type": "action", "title": "...", "description": "...", "sql": "SELECT ... FROM {target_table} WHERE ...", "action_id": "{id}", "params": {}}

    The SQL must be a SELECT that finds the target row(s). Include enough columns for the user to verify the targets.
    """
  end
end
