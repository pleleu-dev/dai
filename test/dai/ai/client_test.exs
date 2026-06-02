defmodule Dai.AI.ClientTest do
  use ExUnit.Case, async: true

  alias Dai.AI.Client

  describe "generate_plan/3 without an API key" do
    test "returns {:error, :api_error} before attempting any HTTP call" do
      # No ANTHROPIC_API_KEY is configured in the test environment, so the
      # client short-circuits at key resolution rather than calling Claude.
      assert {:error, :api_error} = Client.generate_plan("how many users?", "schema")
    end
  end

  describe "send_messages/2 without an API key" do
    test "returns {:error, :api_error}" do
      assert {:error, :api_error} =
               Client.send_messages([%{role: "user", content: "hi"}])
    end
  end

  test "implements the ClientBehaviour contract" do
    assert Dai.AI.ClientBehaviour in (Client.module_info(:attributes)[:behaviour] || [])
  end
end
