defmodule Dai.AI.QueryPipeline do
  @moduledoc "Orchestrates the full NL-to-result pipeline."

  alias Dai.AI.{PlanValidator, SqlExecutor, ResultAssembler}

  def run(prompt, schema_context, opts \\ []) do
    scope = Keyword.get(opts, :scope)
    client = Keyword.get(opts, :client, Dai.Config.ai_client())

    with {:ok, plan} <- client.generate_plan(prompt, schema_context, scope: scope) do
      run_from_plan(plan, prompt, scope)
    end
  end

  def run_from_plan(plan, prompt, scope \\ nil)

  def run_from_plan(%{"needs_clarification" => true} = plan, prompt, _scope) do
    ResultAssembler.assemble_clarification(plan, prompt)
  end

  def run_from_plan(%{"type" => "action"} = plan, prompt, scope) do
    with {:ok, validated} <- PlanValidator.validate(plan, scope),
         {:ok, query_result} <- SqlExecutor.execute(validated, scope) do
      ResultAssembler.assemble_action_confirmation(validated, query_result, prompt)
    end
  end

  def run_from_plan(plan, prompt, scope) do
    with {:ok, validated} <- PlanValidator.validate(plan, scope),
         {:ok, query_result} <- SqlExecutor.execute(validated, scope) do
      ResultAssembler.assemble(validated, query_result, prompt)
    end
  end
end
