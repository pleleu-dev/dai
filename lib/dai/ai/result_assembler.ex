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
end
