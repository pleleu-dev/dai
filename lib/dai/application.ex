defmodule Dai.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if standalone?() do
      children = [
        DaiWeb.Telemetry,
        Dai.Repo,
        {DNSCluster, query: Application.get_env(:dai, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Dai.PubSub},
        Dai.SchemaContext,
        Dai.SchemaExplorer,
        DaiWeb.Endpoint
      ]

      opts = [strategy: :one_for_one, name: Dai.Supervisor]
      Supervisor.start_link(children, opts)
    else
      # Library mode: clear standalone config to prevent Dai.Repo from
      # being auto-started by Ecto and DaiWeb.Endpoint from initializing.
      Application.put_env(:dai, :ecto_repos, [])
      Application.delete_env(:dai, DaiWeb.Endpoint)

      opts = [strategy: :one_for_one, name: Dai.Supervisor]
      Supervisor.start_link([], opts)
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    if standalone?() do
      DaiWeb.Endpoint.config_change(changed, removed)
    end

    :ok
  end

  defp standalone? do
    Application.get_env(:dai, :standalone, false)
  end
end
