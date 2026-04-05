defmodule Dai.DashboardLive do
  use Phoenix.LiveView

  alias Dai.AI.{ActionExecutor, ActionRegistry, QueryPipeline, Result, ResultAssembler}
  alias Dai.{DashboardLayout, DashboardPreferences, Folders, Icons, SchemaContext, SchemaExplorer}

  import Dai.SchemaExplorerComponents, only: [empty_state: 1, schema_panel_content: 1]
  import Dai.SidebarComponents, only: [folder_panel: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <.dai_wrapper host_layout={@dai_host_layout} flash={@flash}>
      <div class="flex h-full" id="dashboard-panels">
        <%!-- LEFT PANEL: Query input + GridStack card grid --%>
        <div
          style={"width: #{@panel_sizes["main_split"]}%"}
          class="min-w-0 flex flex-col"
        >
          <div class="p-6 pb-0 shrink-0">
            <.query_input form={@form} loading={@loading} />
          </div>
          <.loading_skeleton :if={@loading} />
          <div class="flex-1 min-h-0 overflow-y-auto px-6 pb-6">
            <.empty_state schema_explorer={@schema_explorer} />
            <div
              id="results-grid"
              phx-hook="DaiGridStack"
              data-gs-layout={Jason.encode!(@saved_layouts)}
              class="grid-stack"
              phx-update="ignore"
            >
            </div>
          </div>
        </div>

        <%!-- HORIZONTAL RESIZER --%>
        <div
          id="main-resizer"
          phx-hook="DaiPanelResizer"
          data-direction="horizontal"
          data-name="main_split"
          class="dai-resizer"
        >
          <div class="dai-resizer-handle-h"></div>
        </div>

        <%!-- RIGHT PANEL: Folders + Schema Explorer --%>
        <div
          style={"width: #{100 - @panel_sizes["main_split"]}%"}
          class="min-w-0 flex flex-col border-l border-base-300 bg-base-200/30"
          id="right-panel"
        >
          <%!-- Folders section --%>
          <div style={"height: #{@panel_sizes["right_split"]}%"} class="min-h-0 flex flex-col">
            <.folder_panel
              folders={@folders}
              active_folder_id={@active_folder_id}
              folder_queries={@folder_queries}
            />
          </div>

          <%!-- VERTICAL RESIZER --%>
          <div
            id="right-resizer"
            phx-hook="DaiPanelResizer"
            data-direction="vertical"
            data-name="right_split"
            class="dai-resizer"
          >
            <div class="dai-resizer-handle-v"></div>
          </div>

          <%!-- Schema Explorer section --%>
          <div style={"height: #{100 - @panel_sizes["right_split"]}%"} class="min-h-0 flex flex-col">
            <.schema_panel_content
              schema_explorer={@schema_explorer}
              explorer_focus={@explorer_focus}
              explorer_suggestions={@explorer_suggestions}
              explorer_loading={@explorer_loading}
            />
          </div>
        </div>
      </div>
    </.dai_wrapper>
    """
  end

  # When a host layout is active, render content directly (host layout wraps us)
  attr :host_layout, :boolean, required: true
  attr :flash, :map, required: true
  slot :inner_block, required: true

  defp dai_wrapper(%{host_layout: true} = assigns) do
    ~H"""
    {render_slot(@inner_block)}
    """
  end

  defp dai_wrapper(assigns) do
    ~H"""
    <Dai.Layouts.app flash={@flash}>
      {render_slot(@inner_block)}
    </Dai.Layouts.app>
    """
  end

  # --- Private components ---

  attr :form, :any, required: true
  attr :loading, :boolean, required: true

  defp query_input(assigns) do
    ~H"""
    <div class="mb-10">
      <.form for={@form} phx-submit="query" id="query-form">
        <div class={[
          "relative flex items-center gap-2 rounded-2xl border bg-base-200/50 p-1.5 transition-all duration-300",
          @loading && "border-primary/40 shadow-[0_0_20px_-4px] shadow-primary/20",
          !@loading &&
            "border-base-300 hover:border-primary/30 focus-within:border-primary/50 focus-within:shadow-[0_0_24px_-6px] focus-within:shadow-primary/15"
        ]}>
          <div class={[
            "pl-3 shrink-0 transition-colors duration-300",
            @loading && "text-primary animate-pulse",
            !@loading && "text-base-content/30"
          ]}>
            <Icons.sparkles class="size-5" />
          </div>

          <input
            type="text"
            name={@form[:prompt].name}
            id={@form[:prompt].id}
            value={Phoenix.HTML.Form.normalize_value("text", @form[:prompt].value)}
            placeholder="Ask anything about your data..."
            autocomplete="off"
            phx-debounce="300"
            class="flex-1 bg-transparent border-none text-base-content placeholder-base-content/30 text-base py-3 px-2 focus:outline-none"
          />

          <button
            type="submit"
            disabled={@loading}
            class={[
              "shrink-0 flex items-center gap-2 rounded-xl px-5 py-2.5 font-medium text-sm transition-all duration-200",
              @loading && "bg-primary/20 text-primary cursor-wait",
              !@loading && "bg-primary text-primary-content hover:brightness-110 active:scale-[0.97]"
            ]}
          >
            <%= if @loading do %>
              <span class="loading loading-spinner loading-xs"></span>
              <span>Thinking</span>
              <span class="inline-flex gap-0.5">
                <span class="animate-bounce" style="animation-delay: 0ms">.</span>
                <span class="animate-bounce" style="animation-delay: 150ms">.</span>
                <span class="animate-bounce" style="animation-delay: 300ms">.</span>
              </span>
            <% else %>
              <Icons.arrow_up class="size-4" />
              <span>Ask</span>
            <% end %>
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <div class="mb-6">
      <div class="card card-border bg-base-100 p-5">
        <div class="skeleton h-4 w-1/3 mb-3"></div>
        <div class="skeleton h-3 w-1/2 mb-5"></div>
        <div class="skeleton h-36"></div>
      </div>
    </div>
    """
  end

  # --- LiveView callbacks ---

  @impl true
  def mount(_params, session, socket) do
    host_layout = Map.get(session, "dai_host_layout", false)
    user_token = Map.get(session, "dai_user_token", generate_fallback_token())

    prefs = DashboardPreferences.get_preferences(user_token)
    saved_layouts = DashboardLayout.get_layouts(user_token)

    {:ok,
     socket
     |> assign(
       loading: false,
       current_prompt: nil,
       task_ref: nil,
       pending_tasks: %{},
       pending_actions: %{},
       dai_host_layout: host_layout,
       user_token: user_token,
       saved_layouts: saved_layouts,
       panel_sizes: prefs.panel_sizes,
       folders: Folders.list_folders(),
       active_folder_id: nil,
       folder_queries: [],
       schema_explorer: SchemaExplorer.get(),
       explorer_focus: [],
       explorer_suggestions: [],
       explorer_loading: false,
       explorer_suggestion_ref: nil
     )
     |> assign(:form, to_form(%{"prompt" => ""}, as: :query))}
  end

  defp generate_fallback_token do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  # --- Query events ---

  @impl true
  def handle_event("query", %{"query" => %{"prompt" => prompt}}, socket) when prompt != "" do
    run_query(prompt, socket)
  end

  def handle_event("query", %{"prompt" => prompt}, socket) when prompt != "" do
    run_query(prompt, socket)
  end

  def handle_event("query", _params, socket), do: {:noreply, socket}

  def handle_event("dismiss", %{"id" => id}, socket) do
    {:noreply, push_event(socket, "remove_card", %{id: id})}
  end

  def handle_event("retry", %{"prompt" => prompt}, socket) do
    run_query(prompt, socket)
  end

  def handle_event("confirm_action", %{"result-id" => result_id}, socket) do
    case Map.pop(socket.assigns.pending_actions, result_id) do
      {nil, _} ->
        {:noreply, socket}

      {pending_result, remaining} ->
        result_card = execute_pending_action(pending_result)

        {:noreply,
         socket
         |> push_event("remove_card", %{id: result_id})
         |> push_card(result_card)
         |> assign(pending_actions: remaining)}
    end
  end

  def handle_event("run_suggestion", %{"text" => text}, socket) do
    run_query(text, socket)
  end

  def handle_event("edit_suggestion", %{"text" => text}, socket) do
    {:noreply, assign(socket, form: to_form(%{"prompt" => text}, as: :query))}
  end

  # --- Sidebar events ---

  def handle_event("save_query", %{"folder-id" => folder_id, "prompt" => prompt} = params, socket) do
    case Folders.create_saved_query(%{
           folder_id: folder_id,
           prompt: prompt,
           title: params["title"]
         }) do
      {:ok, _} -> {:noreply, reload_folder_queries(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("save_query_new_folder", %{"prompt" => prompt} = params, socket) do
    case Folders.save_query_to_new_folder(prompt, params["title"], length(socket.assigns.folders)) do
      {:ok, %{folder: folder}} ->
        {:noreply,
         socket
         |> reload_folders()
         |> assign(
           active_folder_id: folder.id,
           folder_queries: Folders.list_saved_queries(folder.id)
         )}

      {:error, _, _, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("create_folder", %{"name" => name}, socket) when name != "" do
    case Folders.create_folder(%{
           name: name,
           position: length(socket.assigns.folders)
         }) do
      {:ok, folder} ->
        {:noreply,
         socket
         |> reload_folders()
         |> assign(active_folder_id: folder.id, folder_queries: [])}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("create_folder", _params, socket) do
    case Folders.create_folder(%{
           name: Folders.default_folder_name(),
           position: length(socket.assigns.folders)
         }) do
      {:ok, folder} ->
        {:noreply,
         socket
         |> reload_folders()
         |> assign(active_folder_id: folder.id, folder_queries: [])}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("load_folder", %{"id" => id}, socket) do
    new_active = if socket.assigns.active_folder_id == id, do: nil, else: id

    {:noreply,
     assign(socket,
       active_folder_id: new_active,
       folder_queries: if(new_active, do: Folders.list_saved_queries(new_active), else: [])
     )}
  end

  def handle_event("run_saved_query", %{"prompt" => prompt}, socket) do
    run_query(prompt, socket)
  end

  def handle_event("load_all_folder_queries", %{"id" => folder_id}, socket) do
    queries = Folders.list_saved_queries(folder_id)

    pending =
      Map.new(queries, fn query ->
        task = Task.async(fn -> QueryPipeline.run(query.prompt, SchemaContext.get()) end)
        {task.ref, query.prompt}
      end)

    {:noreply,
     assign(socket,
       pending_tasks: Map.merge(socket.assigns.pending_tasks, pending),
       loading: pending != %{},
       active_folder_id: folder_id
     )}
  end

  def handle_event("delete_folder", %{"id" => id}, socket) do
    case Folders.delete_folder_by_id(id) do
      {:ok, _} ->
        new_active =
          if socket.assigns.active_folder_id == id, do: nil, else: socket.assigns.active_folder_id

        {:noreply,
         socket
         |> reload_folders()
         |> assign(
           active_folder_id: new_active,
           folder_queries: if(new_active, do: Folders.list_saved_queries(new_active), else: [])
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_saved_query", %{"id" => id}, socket) do
    case Folders.delete_saved_query_by_id(id) do
      {:ok, _} -> {:noreply, reload_folder_queries(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("rename_folder", %{"id" => id, "name" => name}, socket) do
    case Folders.rename_folder(id, name) do
      {:ok, _} -> {:noreply, reload_folders(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("rename_saved_query", %{"id" => id, "title" => title}, socket) do
    case Folders.rename_saved_query(id, title) do
      {:ok, _} -> {:noreply, reload_folder_queries(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  # --- Layout events ---

  def handle_event("layout_changed", %{"cards" => cards}, socket) do
    DashboardLayout.save_layouts(socket.assigns.user_token, cards)
    {:noreply, socket}
  end

  def handle_event("panel_resized", %{"name" => name, "size" => size}, socket) do
    panel_sizes = Map.put(socket.assigns.panel_sizes, name, size)
    DashboardPreferences.save_panel_sizes(socket.assigns.user_token, panel_sizes)
    {:noreply, assign(socket, panel_sizes: panel_sizes)}
  end

  # --- Schema panel events ---

  def handle_event("select_table", %{"name" => name}, socket) do
    focus = socket.assigns.explorer_focus

    if name in focus do
      {:noreply, socket}
    else
      new_focus = focus ++ [name]
      socket = assign(socket, explorer_focus: new_focus, explorer_loading: true)
      send(self(), {:fetch_suggestions, new_focus})
      {:noreply, socket}
    end
  end

  def handle_event("deselect_table", %{"name" => name}, socket) do
    new_focus = List.delete(socket.assigns.explorer_focus, name)

    if new_focus == [] do
      {:noreply,
       assign(socket, explorer_focus: [], explorer_suggestions: [], explorer_loading: false)}
    else
      socket = assign(socket, explorer_focus: new_focus, explorer_loading: true)
      send(self(), {:fetch_suggestions, new_focus})
      {:noreply, socket}
    end
  end

  def handle_event("reset_explorer", _params, socket) do
    {:noreply,
     assign(socket, explorer_focus: [], explorer_suggestions: [], explorer_loading: false)}
  end

  # --- Task results ---

  @impl true
  def handle_info({:fetch_suggestions, table_names}, socket) do
    task =
      Task.async(fn ->
        {:explorer_suggestions, SchemaExplorer.suggest(table_names)}
      end)

    {:noreply, assign(socket, explorer_suggestion_ref: task.ref)}
  end

  def handle_info({ref, {:explorer_suggestions, suggestions}}, socket)
      when socket.assigns.explorer_suggestion_ref == ref do
    Process.demonitor(ref, [:flush])

    {:noreply,
     assign(socket,
       explorer_suggestions: suggestions,
       explorer_loading: false,
       explorer_suggestion_ref: nil
     )}
  end

  # Single query result (from run_query)
  def handle_info({ref, result}, socket) when socket.assigns.task_ref == ref do
    Process.demonitor(ref, [:flush])
    card = result_to_card(result, socket.assigns.current_prompt)

    socket =
      socket
      |> push_card(card)
      |> assign(loading: false, task_ref: nil)
      |> maybe_store_pending_action(card)

    {:noreply, socket}
  end

  # Batch query result (from load_all_folder_queries)
  def handle_info({ref, result}, socket) do
    pending = socket.assigns.pending_tasks

    if Map.has_key?(pending, ref) do
      Process.demonitor(ref, [:flush])
      remaining = Map.delete(pending, ref)

      {:noreply,
       socket
       |> push_card(result_to_card(result, pending[ref]))
       |> assign(pending_tasks: remaining, loading: remaining != %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket)
      when socket.assigns.task_ref == ref do
    {:noreply, assign(socket, loading: false, task_ref: nil)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) do
    pending = socket.assigns.pending_tasks

    if Map.has_key?(pending, ref) do
      remaining = Map.delete(pending, ref)
      {:noreply, assign(socket, pending_tasks: remaining, loading: remaining != %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Private helpers ---

  defp run_query(prompt, socket) do
    task = Task.async(fn -> QueryPipeline.run(prompt, SchemaContext.get()) end)

    {:noreply,
     assign(socket,
       loading: true,
       current_prompt: prompt,
       task_ref: task.ref,
       form: to_form(%{"prompt" => ""}, as: :query)
     )}
  end

  defp result_to_card({:ok, result}, _prompt) do
    %{result | layout_key: DashboardLayout.layout_key(result.prompt)}
  end

  defp result_to_card({:error, reason}, prompt) do
    error = Result.error(reason, prompt)
    %{error | layout_key: DashboardLayout.layout_key(prompt)}
  end

  defp push_card(socket, card) do
    assigns = %{result: card, folders: socket.assigns.folders}

    html =
      rendered_to_string(
        Dai.DashboardComponents.result_card(assigns)
      )

    push_event(socket, "add_card", %{
      id: card.id,
      html: html,
      layout_key: card.layout_key,
      card_type: to_string(card.type)
    })
  end

  defp rendered_to_string(rendered) do
    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp maybe_store_pending_action(socket, %Result{type: :action_confirmation} = result) do
    assign(socket,
      pending_actions: Map.put(socket.assigns.pending_actions, result.id, result)
    )
  end

  defp maybe_store_pending_action(socket, _result), do: socket

  defp execute_pending_action(pending_result) do
    case ActionRegistry.lookup(pending_result.action_id) do
      {:ok, action_module} ->
        outcome =
          ActionExecutor.execute_all(
            action_module,
            pending_result.action_targets,
            pending_result.action_params
          )

        ResultAssembler.assemble_action_result(outcome, pending_result.prompt, action_module)

      :error ->
        Result.error(:invalid_action, pending_result.prompt)
    end
  end

  defp reload_folders(socket), do: assign(socket, folders: Folders.list_folders())

  defp reload_folder_queries(socket) do
    case socket.assigns.active_folder_id do
      nil -> socket
      id -> assign(socket, folder_queries: Folders.list_saved_queries(id))
    end
  end
end
