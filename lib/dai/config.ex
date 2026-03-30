defmodule Dai.Config do
  @moduledoc "Centralized configuration reader for the Dai library."

  def repo do
    Application.fetch_env!(:dai, :repo)
  end

  def schema_contexts do
    Application.get_env(:dai, :schema_contexts, [])
  end

  def extra_schemas do
    Application.get_env(:dai, :extra_schemas, [])
  end

  def ai_config do
    Application.get_env(:dai, :ai, [])
  end

  def api_key do
    Keyword.get(ai_config(), :api_key)
  end

  def model do
    Keyword.get(ai_config(), :model, "claude-sonnet-4-6")
  end

  def max_tokens do
    Keyword.get(ai_config(), :max_tokens, 1024)
  end
end
