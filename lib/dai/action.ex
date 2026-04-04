defmodule Dai.Action do
  @moduledoc "Behaviour for custom actions that can be executed from the Dai dashboard."

  @type target :: map()
  @type params :: map()

  @callback id() :: String.t()
  @callback label() :: String.t()
  @callback description() :: String.t()
  @callback target_table() :: String.t()
  @callback target_key() :: String.t()
  @callback confirm_message(target()) :: String.t()
  @callback execute(target(), params()) :: {:ok, term()} | {:error, term()}
end
