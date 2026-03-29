defmodule Dai.AI.QueryPipeline do
  @moduledoc "Orchestrates the full NL-to-result pipeline."

  alias Dai.AI.{Client, PlanValidator, SqlExecutor, ResultAssembler}

  def run(prompt, schema_context) do
    with {:ok, plan} <- Client.generate_plan(prompt, schema_context) do
      run_from_plan(plan, prompt)
    end
  end

  def run_from_plan(%{"needs_clarification" => true} = plan, prompt) do
    ResultAssembler.assemble_clarification(plan, prompt)
  end

  def run_from_plan(plan, prompt) do
    with {:ok, validated} <- PlanValidator.validate(plan),
         {:ok, query_result} <- SqlExecutor.execute(validated) do
      ResultAssembler.assemble(validated, query_result, prompt)
    end
  end
end
