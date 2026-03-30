defmodule Dai.Config do
  @moduledoc "Centralized configuration reader for the Dai library."

  @spec repo() :: module()
  def repo do
    case Application.get_env(:dai, :repo) do
      nil ->
        raise ArgumentError,
              "Dai requires :repo to be configured. Add `config :dai, repo: MyApp.Repo` to your config."

      repo ->
        repo
    end
  end

  @spec schema_contexts() :: [module()]
  def schema_contexts do
    Application.get_env(:dai, :schema_contexts, [])
  end

  @spec extra_schemas() :: [module()]
  def extra_schemas do
    Application.get_env(:dai, :extra_schemas, [])
  end

  @spec ai_config() :: keyword()
  def ai_config do
    Application.get_env(:dai, :ai, [])
  end

  @spec api_key() :: String.t() | nil
  def api_key do
    Keyword.get(ai_config(), :api_key)
  end

  @spec model() :: String.t()
  def model do
    Keyword.get(ai_config(), :model, "claude-sonnet-4-6")
  end

  @spec max_tokens() :: pos_integer()
  def max_tokens do
    Keyword.get(ai_config(), :max_tokens, 1024)
  end
end
