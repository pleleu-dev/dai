defmodule Dai.AI.ResultAssembler do
  @moduledoc "Builds a Result struct from a validated plan and query result."

  alias Dai.AI.{Component, Result}

  def assemble(plan, query_result, prompt) do
    {:ok,
     %Result{
       id: Result.generate_id(),
       type: Component.to_atom(plan["component"]),
       title: plan["title"],
       description: plan["description"],
       config: plan["config"],
       data: query_result,
       prompt: prompt,
       timestamp: DateTime.utc_now()
     }}
  end

  def assemble_clarification(%{"question" => question}, prompt) do
    {:ok,
     %Result{
       id: Result.generate_id(),
       type: :clarification,
       title: "Clarification Needed",
       description: question,
       question: question,
       prompt: prompt,
       timestamp: DateTime.utc_now()
     }}
  end

  def assemble_action_confirmation(plan, query_result, prompt) do
    {:ok,
     %Result{
       id: Result.generate_id(),
       type: :action_confirmation,
       title: plan["title"],
       description: plan["description"],
       action_id: plan["action_id"],
       action_targets: query_result.rows,
       action_params: plan["params"] || %{},
       data: query_result,
       prompt: prompt,
       timestamp: DateTime.utc_now()
     }}
  end

  def assemble_action_result(outcome, prompt, action_module) do
    build_action_result(outcome, prompt, action_module)
  end

  defp build_action_result({:ok, successes}, prompt, action_module) do
    count = length(successes)

    %Result{
      id: Result.generate_id(),
      type: :action_result,
      title: action_module.label(),
      description:
        "Successfully completed #{action_module.label()} on #{count} #{pluralize(count, "target")}.",
      prompt: prompt,
      timestamp: DateTime.utc_now()
    }
  end

  defp build_action_result({:partial, successes, failures}, prompt, action_module) do
    succeeded = length(successes)
    failed = length(failures)
    total = succeeded + failed
    {_target, first_reason} = hd(failures)

    %Result{
      id: Result.generate_id(),
      type: :action_result,
      title: action_module.label(),
      description: "Completed #{succeeded} of #{total}. #{failed} failed: #{first_reason}",
      error: "#{failed} of #{total} failed",
      prompt: prompt,
      timestamp: DateTime.utc_now()
    }
  end

  defp build_action_result({:error, reason}, prompt, action_module) do
    %Result{
      id: Result.generate_id(),
      type: :action_result,
      title: action_module.label(),
      description: "Failed: #{reason}",
      error: to_string(reason),
      prompt: prompt,
      timestamp: DateTime.utc_now()
    }
  end

  defp pluralize(1, word), do: word
  defp pluralize(_, word), do: word <> "s"
end
