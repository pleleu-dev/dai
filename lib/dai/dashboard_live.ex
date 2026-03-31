defmodule Dai.DashboardLive do
  use Phoenix.LiveView

  alias Dai.AI.{QueryPipeline, Result}
  alias Dai.{Folders, Icons, SchemaContext}

  import Dai.DashboardComponents
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
            <.query_input form={@form} loading={@loading} />
            <.loading_skeleton :if={@loading} />
            <.results_grid
              streams={@streams}
              folders={@folders}
              save_dropdown_open={@save_dropdown_open}
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
      <div class="rounded-xl border border-base-300/50 bg-base-200/30 p-5 animate-pulse">
        <div class="h-4 bg-base-300/60 rounded-lg w-1/3 mb-3"></div>
        <div class="h-3 bg-base-300/40 rounded-lg w-1/2 mb-5"></div>
        <div class="h-36 bg-base-300/30 rounded-lg"></div>
      </div>
    </div>
    """
  end

  attr :streams, :any, required: true
  attr :folders, :list, default: []
  attr :save_dropdown_open, :string, default: nil

  defp results_grid(assigns) do
    ~H"""
    <div
      id="results"
      phx-update="stream"
      class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
    >
      <div id="empty-state" class="hidden only:block col-span-full text-center py-24">
        <div class="text-base-content/20 mb-6">
          <Icons.chart_bar class="size-20 mx-auto" />
        </div>
        <h2 class="text-2xl font-semibold text-base-content/40 mb-3">
          Ask anything about your data
        </h2>
        <p class="text-base-content/30 text-sm max-w-sm mx-auto leading-relaxed">
          Type a question in plain English and get instant charts, metrics, and tables.
        </p>
      </div>
      <div :for={{dom_id, result} <- @streams.results} id={dom_id}>
        <.result_card
          result={result}
          folders={@folders}
          save_dropdown_open={@save_dropdown_open}
        />
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
       save_dropdown_open: nil
     )
     |> assign(:form, to_form(%{"prompt" => ""}, as: :query))
     |> stream(:results, [])}
  end

  @impl true
  # Form submission (wrapped in :query key by <.form as={:query}>)
  def handle_event("query", %{"query" => %{"prompt" => prompt}}, socket) when prompt != "" do
    run_query(prompt, socket)
  end

  # Clarification card / retry (bare prompt key)
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

  # --- Sidebar events ---

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, sidebar_open: !socket.assigns.sidebar_open)}
  end

  def handle_event("toggle_save_dropdown", %{"id" => id}, socket) do
    new_val = if socket.assigns.save_dropdown_open == id, do: nil, else: id
    {:noreply, assign(socket, save_dropdown_open: new_val)}
  end

  def handle_event("save_query", %{"folder-id" => folder_id, "prompt" => prompt} = params, socket) do
    title = Map.get(params, "title")

    case Folders.create_saved_query(%{folder_id: folder_id, prompt: prompt, title: title}) do
      {:ok, _query} ->
        {:noreply,
         socket
         |> assign(save_dropdown_open: nil)
         |> reload_folder_queries()}

      {:error, _changeset} ->
        {:noreply, assign(socket, save_dropdown_open: nil)}
    end
  end

  def handle_event("save_query_new_folder", %{"prompt" => prompt} = params, socket) do
    title = Map.get(params, "title")
    position = length(socket.assigns.folders)

    with {:ok, folder} <- Folders.create_folder(%{name: "New Folder", position: position}),
         {:ok, _query} <-
           Folders.create_saved_query(%{folder_id: folder.id, prompt: prompt, title: title}) do
      {:noreply,
       socket
       |> assign(
         folders: Folders.list_folders(),
         active_folder_id: folder.id,
         folder_queries: Folders.list_saved_queries(folder.id),
         sidebar_open: true,
         save_dropdown_open: nil
       )}
    else
      _ -> {:noreply, assign(socket, save_dropdown_open: nil)}
    end
  end

  def handle_event("create_folder", _params, socket) do
    position = length(socket.assigns.folders)

    case Folders.create_folder(%{name: "New Folder", position: position}) do
      {:ok, folder} ->
        {:noreply,
         socket
         |> assign(
           folders: Folders.list_folders(),
           active_folder_id: folder.id,
           folder_queries: []
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("load_folder", %{"id" => id}, socket) do
    new_active = if socket.assigns.active_folder_id == id, do: nil, else: id

    {:noreply,
     socket
     |> assign(
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
       pending_tasks: Map.merge(socket.assigns[:pending_tasks] || %{}, pending),
       loading: pending != %{},
       active_folder_id: folder_id,
       sidebar_open: true
     )}
  end

  def handle_event("delete_folder", %{"id" => id}, socket) do
    folder = Folders.get_folder!(id)

    case Folders.delete_folder(folder) do
      {:ok, _} ->
        new_active =
          if socket.assigns.active_folder_id == id, do: nil, else: socket.assigns.active_folder_id

        {:noreply,
         socket
         |> assign(
           folders: Folders.list_folders(),
           active_folder_id: new_active,
           folder_queries: if(new_active, do: Folders.list_saved_queries(new_active), else: [])
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_saved_query", %{"id" => id}, socket) do
    query = Folders.get_saved_query!(id)

    case Folders.delete_saved_query(query) do
      {:ok, _} -> {:noreply, reload_folder_queries(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("rename_folder", %{"id" => id, "name" => name}, socket) do
    folder = Folders.get_folder!(id)

    case Folders.update_folder(folder, %{name: name}) do
      {:ok, _} -> {:noreply, assign(socket, folders: Folders.list_folders())}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("rename_saved_query", %{"id" => id, "title" => title}, socket) do
    query = Folders.get_saved_query!(id)

    case Folders.update_saved_query(query, %{title: title}) do
      {:ok, _} -> {:noreply, reload_folder_queries(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  # Single query result (from run_query)
  def handle_info({ref, result}, socket) when socket.assigns.task_ref == ref do
    Process.demonitor(ref, [:flush])

    card =
      case result do
        {:ok, r} -> r
        {:error, reason} -> Result.error(reason, socket.assigns.current_prompt)
      end

    {:noreply,
     socket
     |> stream_insert(:results, card, at: 0)
     |> assign(loading: false, task_ref: nil)}
  end

  # Batch query result (from load_all_folder_queries)
  def handle_info({ref, result}, socket) do
    pending = socket.assigns[:pending_tasks] || %{}

    if Map.has_key?(pending, ref) do
      Process.demonitor(ref, [:flush])
      prompt = pending[ref]
      remaining = Map.delete(pending, ref)

      card =
        case result do
          {:ok, r} -> r
          {:error, reason} -> Result.error(reason, prompt)
        end

      {:noreply,
       socket
       |> stream_insert(:results, card, at: 0)
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
    pending = socket.assigns[:pending_tasks] || %{}

    if Map.has_key?(pending, ref) do
      remaining = Map.delete(pending, ref)
      {:noreply, assign(socket, pending_tasks: remaining, loading: remaining != %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

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

  defp reload_folder_queries(socket) do
    case socket.assigns.active_folder_id do
      nil -> socket
      id -> assign(socket, folder_queries: Folders.list_saved_queries(id))
    end
  end
end
