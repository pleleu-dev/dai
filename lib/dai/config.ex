defmodule Dai.Config do
  @moduledoc "Centralized configuration reader for the Dai library."

  @default_statement_timeout_ms 15_000
  @default_max_rows 1_000
  @default_max_prompt_length 2_000
  @default_rate_limit %{limit: 20, window_ms: 60_000}

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

  @spec actions() :: [module()]
  def actions do
    Application.get_env(:dai, :actions, [])
  end

  @spec query_scope() :: map() | nil
  def query_scope do
    Application.get_env(:dai, :query_scope)
  end

  @doc """
  Module implementing `Dai.AI.ClientBehaviour` used to talk to Claude.

  Defaults to `Dai.AI.Client`; tests inject a Mox double via this key (or the
  `:client` option on `Dai.AI.QueryPipeline.run/3`).
  """
  @spec ai_client() :: module()
  def ai_client do
    Application.get_env(:dai, :ai_client, Dai.AI.Client)
  end

  @doc """
  Optional dedicated read-only Ecto repo used to execute AI-generated SQL.

  When the host configures a Postgres role with only `GRANT SELECT` and wires
  it to a second Ecto repo, set `config :dai, readonly_repo: MyApp.ReadOnlyRepo`.
  Returns `nil` when not configured; callers should use `sql_repo/0`.
  """
  @spec readonly_repo() :: module() | nil
  def readonly_repo do
    Application.get_env(:dai, :readonly_repo)
  end

  @doc """
  Repo used to execute AI-generated SQL: the dedicated `readonly_repo/0` when
  configured, otherwise the primary `repo/0` (constrained by a READ ONLY
  transaction at the execution boundary).
  """
  @spec sql_repo() :: module()
  def sql_repo do
    readonly_repo() || repo()
  end

  @doc "Per-statement timeout (ms) applied to AI-generated SQL. Default 15s."
  @spec statement_timeout_ms() :: pos_integer()
  def statement_timeout_ms do
    Application.get_env(:dai, :statement_timeout_ms, @default_statement_timeout_ms)
  end

  @doc "Hard upper bound on rows returned by any AI-generated query. Default 1000."
  @spec max_rows() :: pos_integer()
  def max_rows do
    Application.get_env(:dai, :max_rows, @default_max_rows)
  end

  @doc "Maximum accepted length (characters) of a user prompt. Default 2000."
  @spec max_prompt_length() :: pos_integer()
  def max_prompt_length do
    Application.get_env(:dai, :max_prompt_length, @default_max_prompt_length)
  end

  @doc """
  Per-socket query rate limit as `%{limit: n, window_ms: ms}`.

  Default allows 20 queries per 60s window.
  """
  @spec rate_limit() :: %{limit: pos_integer(), window_ms: pos_integer()}
  def rate_limit do
    Application.get_env(:dai, :rate_limit, @default_rate_limit)
  end
end
