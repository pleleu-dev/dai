defmodule Dai.DashboardLive do
  use Phoenix.LiveView

  alias Dai.AI.{QueryPipeline, Result}
  alias Dai.{Icons, SchemaContext}

  import Dai.DashboardComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Dai.Layouts.app flash={@flash}>
      <div class="max-w-7xl mx-auto">
        <.query_input form={@form} loading={@loading} />
        <.loading_skeleton :if={@loading} />
        <.results_grid streams={@streams} />
      </div>
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
        <.result_card result={result} />
      </div>
    </div>
    """
  end

  # --- LiveView callbacks ---

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(loading: false, current_prompt: nil, task_ref: nil)
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

  @impl true
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

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket)
      when socket.assigns.task_ref == ref do
    {:noreply, assign(socket, loading: false, task_ref: nil)}
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
end
