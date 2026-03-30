defmodule Dai.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if standalone?() do
        [
          DaiWeb.Telemetry,
          Dai.Repo,
          {DNSCluster, query: Application.get_env(:dai, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Dai.PubSub},
          Dai.SchemaContext,
          DaiWeb.Endpoint
        ]
      else
        # As a library: start nothing. The host app is responsible for
        # adding Dai.SchemaContext to its own supervision tree.
        []
      end

    opts = [strategy: :one_for_one, name: Dai.Supervisor]
    Supervisor.start_link(children, opts)
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
