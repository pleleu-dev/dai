defmodule Dai.AI.SystemPromptTest do
  use ExUnit.Case, async: true

  alias Dai.AI.SystemPrompt

  describe "build/2" do
    test "embeds the schema context" do
      prompt = SystemPrompt.build("TABLE users (id, email)")
      assert prompt =~ "TABLE users (id, email)"
    end

    test "omits the scoping section when no scope is given" do
      prompt = SystemPrompt.build("schema")
      refute prompt =~ "CRITICAL SCOPING RULE"
    end

    test "includes the scoping rule with the table and column when scope is present" do
      scope = %{column: "org_name", table: "users", value: "Acme"}
      prompt = SystemPrompt.build("schema", scope: scope)

      assert prompt =~ "CRITICAL SCOPING RULE"
      assert prompt =~ "users.org_name"
    end

    test "includes optional scope description when provided" do
      scope = %{
        column: "org_name",
        table: "users",
        value: "Acme",
        description: "Only the current organization"
      }

      prompt = SystemPrompt.build("schema", scope: scope)
      assert prompt =~ "Only the current organization"
    end
  end
end
