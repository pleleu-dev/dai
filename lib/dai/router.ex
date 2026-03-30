defmodule Dai.Router do
  @moduledoc """
  Router helpers for mounting the Dai dashboard.

  ## Usage

      import Dai.Router

      scope "/" do
        pipe_through :browser
        dai_dashboard "/dashboard"
      end
  """

  defmacro dai_dashboard(path, opts \\ []) do
    quote do
      live unquote(path), Dai.DashboardLive, :index, unquote(opts)
    end
  end
end
