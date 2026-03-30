defmodule Dai.ConfigTest do
  use ExUnit.Case, async: true

  alias Dai.Config

  describe "repo/0" do
    test "returns configured repo" do
      assert Config.repo() == Dai.Repo
    end
  end

  describe "schema_contexts/0" do
    test "returns configured schema contexts" do
      contexts = Config.schema_contexts()
      assert is_list(contexts)
    end
  end

  describe "ai_config/0" do
    test "returns AI configuration keyword list" do
      config = Config.ai_config()
      assert is_list(config)
      assert Keyword.get(config, :model) == "claude-sonnet-4-6"
    end
  end

  describe "model/0" do
    test "returns model with default" do
      assert is_binary(Config.model())
    end
  end

  describe "max_tokens/0" do
    test "returns max_tokens with default" do
      assert Config.max_tokens() == 1024
    end
  end
end
