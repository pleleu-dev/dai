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

  ## Security

  Dai cannot authenticate users for you — the host owns the session. For any
  multi-tenant deployment you MUST:

    * **Gate the route.** `pipe_through` an authenticated pipeline and/or pass
      `on_mount:` auth hooks so unauthenticated visitors never reach the
      dashboard.
    * **Pass a trusted `user_token`.** Provide `user_token: &getter/1` deriving a
      stable, signed identifier from your authenticated session (e.g. the user
      or org id). It scopes folders, saved queries, and layout persistence per
      tenant. Without it, Dai falls back to a `connect_params` token that **any
      visitor can forge — it provides NO isolation between users** and is suitable
      for single-tenant / anonymous use only (see `Dai.DashboardLive`).
    * **Pass a `scope_value`** when rows must be filtered to a tenant. Combined
      with `config :dai, :query_scope`, Dai enforces the scope and publishes it
      as the `dai.scope_value` GUC for Postgres RLS policies.

      dai_dashboard "/admin/explore",
        on_mount: [MyAppWeb.RequireAdmin],
        user_token: &MyAppWeb.Auth.dai_user_token/1,
        scope_value: &MyAppWeb.Auth.current_org_id/1

  > #### Demo route {: .warning}
  >
  > The standalone `dai_web/router.ex` mounts the dashboard **unauthenticated**
  > for local development against the demo dataset. Never expose that route as-is
  > in production.
  """

  defmacro dai_dashboard(path, opts \\ []) do
    # opts are AST nodes at macro expansion time — extract them as AST
    layout_ast = Keyword.get(opts, :layout)
    on_mount_ast = Keyword.get(opts, :on_mount, [])
    user_token_getter = Keyword.get(opts, :user_token)
    scope_value_getter = Keyword.get(opts, :scope_value)
    live_opts_ast = Keyword.drop(opts, [:layout, :on_mount, :user_token, :scope_value])

    has_layout = layout_ast != nil

    # Build live_session options: layout, on_mount, session map.
    # Session values with runtime getters (user_token, scope_value) use quote/unquote
    # so they're evaluated at request time, not compile time.
    session_pairs =
      []
      |> then(fn acc ->
        if has_layout, do: [{:layout, layout_ast} | acc], else: acc
      end)
      |> then(fn acc ->
        if on_mount_ast == [], do: acc, else: [{:on_mount, on_mount_ast} | acc]
      end)
      |> then(fn acc ->
        # Build session map with all configured keys
        static_keys = if has_layout, do: [{"dai_host_layout", true}], else: []

        runtime_keys =
          [
            {"dai_user_token", user_token_getter},
            {"dai_scope_value", scope_value_getter}
          ]
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)

        case {static_keys, runtime_keys} do
          {[], []} ->
            acc

          {static, []} ->
            [{:session, Macro.escape(Map.new(static))} | acc]

          {static, _runtime} ->
            # Mix static and runtime values in a quoted map
            static_map = Map.new(static)

            session_ast =
              quote do
                Map.merge(
                  unquote(Macro.escape(static_map)),
                  unquote(Map.new(runtime_keys))
                )
              end

            [{:session, session_ast} | acc]
        end
      end)

    quote do
      # Use alias: false to prevent Phoenix scope from prepending module namespace
      # to Dai.DashboardLive (same pattern used by Phoenix.LiveDashboard.Router)
      scope unquote(path), alias: false do
        live_session :dai_dashboard, unquote(session_pairs) do
          live "/", Dai.DashboardLive, :index, unquote(live_opts_ast)
        end
      end
    end
  end
end
