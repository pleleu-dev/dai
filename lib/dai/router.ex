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
    # opts are AST nodes at macro expansion time — extract them as AST
    layout_ast = Keyword.get(opts, :layout)
    on_mount_ast = Keyword.get(opts, :on_mount, [])
    user_token_getter = Keyword.get(opts, :user_token)
    live_opts_ast = Keyword.drop(opts, [:layout, :on_mount, :user_token])

    has_layout = layout_ast != nil

    # Build session_opts as a keyword list of AST pairs for use in quote.
    # The :session map is a plain Elixir term so it needs Macro.escape/1.
    # The :layout and :on_mount values are already AST and unquote correctly.
    session_pairs =
      []
      |> then(fn acc ->
        if has_layout do
          [{:layout, layout_ast} | acc]
        else
          acc
        end
      end)
      |> then(fn acc ->
        case on_mount_ast do
          [] -> acc
          _ -> [{:on_mount, on_mount_ast} | acc]
        end
      end)
      |> then(fn acc ->
        has_user_token = user_token_getter != nil

        cond do
          has_layout and has_user_token ->
            session_ast =
              quote do
                %{"dai_host_layout" => true, "dai_user_token" => unquote(user_token_getter)}
              end

            [{:session, session_ast} | acc]

          has_layout ->
            [{:session, Macro.escape(%{"dai_host_layout" => true})} | acc]

          has_user_token ->
            session_ast =
              quote do
                %{"dai_user_token" => unquote(user_token_getter)}
              end

            [{:session, session_ast} | acc]

          true ->
            acc
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
