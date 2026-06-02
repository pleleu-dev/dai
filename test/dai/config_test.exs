defmodule Dai.ConfigTest do
  use ExUnit.Case, async: false

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

  describe "readonly_repo/0 and sql_repo/0" do
    test "readonly_repo defaults to nil" do
      assert Config.readonly_repo() == nil
    end

    test "sql_repo falls back to repo when readonly_repo is unset" do
      assert Config.sql_repo() == Config.repo()
    end

    test "sql_repo prefers readonly_repo when configured" do
      Application.put_env(:dai, :readonly_repo, Dai.ReadOnlyRepo)
      on_exit(fn -> Application.delete_env(:dai, :readonly_repo) end)

      assert Config.readonly_repo() == Dai.ReadOnlyRepo
      assert Config.sql_repo() == Dai.ReadOnlyRepo
    end
  end

  describe "statement_timeout_ms/0" do
    test "defaults to 15_000" do
      assert Config.statement_timeout_ms() == 15_000
    end

    test "respects override" do
      Application.put_env(:dai, :statement_timeout_ms, 5_000)
      on_exit(fn -> Application.delete_env(:dai, :statement_timeout_ms) end)
      assert Config.statement_timeout_ms() == 5_000
    end
  end

  describe "max_rows/0" do
    test "defaults to 1_000" do
      assert Config.max_rows() == 1_000
    end

    test "respects override" do
      Application.put_env(:dai, :max_rows, 250)
      on_exit(fn -> Application.delete_env(:dai, :max_rows) end)
      assert Config.max_rows() == 250
    end
  end

  describe "max_prompt_length/0" do
    test "defaults to 2_000" do
      assert Config.max_prompt_length() == 2_000
    end

    test "respects override" do
      Application.put_env(:dai, :max_prompt_length, 500)
      on_exit(fn -> Application.delete_env(:dai, :max_prompt_length) end)
      assert Config.max_prompt_length() == 500
    end
  end

  describe "rate_limit/0" do
    test "defaults to 20 per 60s" do
      assert Config.rate_limit() == %{limit: 20, window_ms: 60_000}
    end

    test "respects override" do
      Application.put_env(:dai, :rate_limit, %{limit: 5, window_ms: 1_000})
      on_exit(fn -> Application.delete_env(:dai, :rate_limit) end)
      assert Config.rate_limit() == %{limit: 5, window_ms: 1_000}
    end
  end
end
