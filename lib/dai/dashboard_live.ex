defmodule Dai.DashboardLive do
  use Phoenix.LiveView

  alias Dai.AI.{QueryPipeline, Result}
  alias Dai.{Folders, Icons, SchemaContext, SchemaExplorer}

  import Dai.DashboardComponents
  import Dai.SchemaExplorerComponents, only: [empty_state: 1, schema_panel: 1]
  import Dai.SidebarComponents, only: [sidebar: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <.dai_wrapper host_layout={@dai_host_layout} flash={@flash}>
      <div class="flex h-full">
        <.sidebar
          sidebar_open={@sidebar_open}
          folders={@folders}
          active_folder_id={@active_folder_id}
          folder_queries={@folder_queries}
        />
        <div class="flex-1 min-w-0 p-6">
          <div class="max-w-7xl mx-auto">
            <div class="flex items-center justify-end mb-2">
              <button
                id="schema-toggle"
                phx-click="toggle_schema_panel"
                class="btn btn-ghost btn-sm gap-1"
              >
                <Icons.table_cells class="size-4" /> Schema
              </button>
            </div>
            <.query_input form={@form} loading={@loading} />
            <.loading_skeleton :if={@loading} />
            <.results_grid streams={@streams} folders={@folders} schema_explorer={@schema_explorer} />
          </div>
        </div>
      </div>
      <.schema_panel
        schema_panel_open={@schema_panel_open}
        schema_explorer={@schema_explorer}
        explorer_focus={@explorer_focus}
        explorer_suggestions={@explorer_suggestions}
        explorer_loading={@explorer_loading}
      />
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

  attr :streams, :any, required: true
  attr :folders, :list, default: []
  attr :schema_explorer, :map, required: true

  defp results_grid(assigns) do
    ~H"""
    <div
      id="results"
      phx-update="stream"
      class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
    >
      <.empty_state schema_explorer={@schema_explorer} />
      <div :for={{dom_id, result} <- @streams.results} id={dom_id}>
        <.result_card result={result} folders={@folders} />
      </div>
    </div>
    """
  end

  # --- LiveView callbacks ---

  @impl true
  def mount(_params, session, socket) do
    host_layout = Map.get(session, "dai_host_layout", false)

    {:ok,
     socket
     |> assign(
       loading: false,
       current_prompt: nil,
       task_ref: nil,
       pending_tasks: %{},
       dai_host_layout: host_layout,
       sidebar_open: false,
       folders: Folders.list_folders(),
       active_folder_id: nil,
       folder_queries: [],
       schema_explorer: SchemaExplorer.get(),
       schema_panel_open: false,
       explorer_focus: [],
       explorer_suggestions: [],
       explorer_loading: false,
       explorer_suggestion_ref: nil
     )
     |> assign(:form, to_form(%{"prompt" => ""}, as: :query))
     |> stream(:results, [])}
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
    {:noreply, stream_delete_by_dom_id(socket, :results, "results-#{id}")}
  end

  def handle_event("retry", %{"prompt" => prompt}, socket) do
    run_query(prompt, socket)
  end

  def handle_event("run_suggestion", %{"text" => text}, socket) do
    run_query(text, socket)
  end

  def handle_event("edit_suggestion", %{"text" => text}, socket) do
    {:noreply, assign(socket, form: to_form(%{"prompt" => text}, as: :query))}
  end

  # --- Sidebar events ---

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, sidebar_open: !socket.assigns.sidebar_open)}
  end

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
           folder_queries: Folders.list_saved_queries(folder.id),
           sidebar_open: true
         )}

      {:error, _, _, _} ->
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
       folder_queries: if(new_active, do: Folders.list_saved_queries(new_active), else: []),
       sidebar_open: true
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
       active_folder_id: folder_id,
       sidebar_open: true
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

  # --- Schema panel events ---

  def handle_event("toggle_schema_panel", _params, socket) do
    {:noreply, assign(socket, schema_panel_open: !socket.assigns.schema_panel_open)}
  end

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

    {:noreply,
     socket
     |> stream_insert(:results, result_to_card(result, socket.assigns.current_prompt), at: 0)
     |> assign(loading: false, task_ref: nil)}
  end

  # Batch query result (from load_all_folder_queries)
  def handle_info({ref, result}, socket) do
    pending = socket.assigns.pending_tasks

    if Map.has_key?(pending, ref) do
      Process.demonitor(ref, [:flush])
      remaining = Map.delete(pending, ref)

      {:noreply,
       socket
       |> stream_insert(:results, result_to_card(result, pending[ref]), at: 0)
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

  defp result_to_card({:ok, result}, _prompt), do: result
  defp result_to_card({:error, reason}, prompt), do: Result.error(reason, prompt)

  defp reload_folders(socket), do: assign(socket, folders: Folders.list_folders())

  defp reload_folder_queries(socket) do
    case socket.assigns.active_folder_id do
      nil -> socket
      id -> assign(socket, folder_queries: Folders.list_saved_queries(id))
    end
  end
end
