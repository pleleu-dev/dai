defmodule Dai.AI.ClientBehaviour do
  @moduledoc """
  Behaviour for the Claude API client.

  Extracting the client contract lets `Dai.AI.QueryPipeline` be tested
  end-to-end with a Mox double (`Dai.AI.ClientMock`) instead of making real HTTP
  calls. `Dai.AI.Client` is the production implementation.
  """

  @doc "Generates a query plan from a natural-language prompt and schema context."
  @callback generate_plan(prompt :: String.t(), schema_context :: String.t(), opts :: keyword()) ::
              {:ok, map() | list()} | {:error, atom()}
end
