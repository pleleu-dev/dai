defmodule Dai.Router do
  @moduledoc """
  Router helpers for mounting the Dai dashboard.

  ## Usage (standalone)

      import Dai.Router

      scope "/" do
        pipe_through :browser
        dai_dashboard "/dashboard"
      end

  ## Usage (embedded in host app layout)

      import Dai.Router

      dai_dashboard "/admin/explore",
        layout: {MyAppWeb.Layouts, :admin},
        on_mount: [MyAppWeb.AdminAuth, MyAppWeb.AdminNav]

  When `:layout` is provided, Dai renders inside the host layout instead of
  its own. When `:on_mount` is provided, the hooks run before Dai's LiveView
  mounts — useful for auth and navigation assigns.
  """

  defmacro dai_dashboard(path, opts \\ []) do
    layout = Keyword.get(opts, :layout)
    on_mount = Keyword.get(opts, :on_mount, [])
    live_opts = Keyword.drop(opts, [:layout, :on_mount])

    session_opts =
      case layout do
        nil -> []
        layout_tuple -> [layout: layout_tuple]
      end

    session_opts =
      case on_mount do
        [] -> session_opts
        hooks -> Keyword.put(session_opts, :on_mount, hooks)
      end

    # Pass a session value so the LiveView knows whether to use its own layout
    session_opts =
      if layout do
        Keyword.put(session_opts, :session, %{"dai_host_layout" => true})
      else
        session_opts
      end

    quote do
      live_session :dai_dashboard, unquote(session_opts) do
        live unquote(path), Dai.DashboardLive, :index, unquote(live_opts)
      end
    end
  end
end
