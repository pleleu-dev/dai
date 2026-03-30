defmodule Dai.DashboardLive do
  use Phoenix.LiveView

  alias Dai.AI.{QueryPipeline, Result}
  alias Dai.SchemaContext

  import Dai.DashboardComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Dai.Layouts.app flash={@flash}>
      <div class="max-w-7xl mx-auto">
        <%!-- Query Input --%>
        <div class="mb-10">
          <.form for={@form} phx-submit="query" id="query-form">
            <div class={[
              "relative flex items-center gap-2 rounded-2xl border bg-base-200/50 p-1.5 transition-all duration-300",
              @loading && "border-primary/40 shadow-[0_0_20px_-4px] shadow-primary/20",
              !@loading && "border-base-300 hover:border-primary/30 focus-within:border-primary/50 focus-within:shadow-[0_0_24px_-6px] focus-within:shadow-primary/15"
            ]}>
              <%!-- Sparkle icon inside the bar --%>
              <div class={[
                "pl-3 shrink-0 transition-colors duration-300",
                @loading && "text-primary animate-pulse",
                !@loading && "text-base-content/30"
              ]}>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-5">
                  <path fill-rule="evenodd" d="M9 4.5a.75.75 0 0 1 .721.544l.813 2.846a3.75 3.75 0 0 0 2.576 2.576l2.846.813a.75.75 0 0 1 0 1.442l-2.846.813a3.75 3.75 0 0 0-2.576 2.576l-.813 2.846a.75.75 0 0 1-1.442 0l-.813-2.846a3.75 3.75 0 0 0-2.576-2.576l-2.846-.813a.75.75 0 0 1 0-1.442l2.846-.813A3.75 3.75 0 0 0 7.466 7.89l.813-2.846A.75.75 0 0 1 9 4.5Z" clip-rule="evenodd" />
                </svg>
              </div>

              <%!-- The actual input — no wrapper div from <.input>, just a raw input --%>
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

              <%!-- Submit button --%>
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
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4">
                    <path fill-rule="evenodd" d="M10 17a.75.75 0 0 1-.75-.75V5.612L5.29 9.77a.75.75 0 0 1-1.08-1.04l5.25-5.5a.75.75 0 0 1 1.08 0l5.25 5.5a.75.75 0 1 1-1.08 1.04l-3.96-4.158V16.25A.75.75 0 0 1 10 17Z" clip-rule="evenodd" />
                  </svg>
                  <span>Ask</span>
                <% end %>
              </button>
            </div>
          </.form>
        </div>

        <%!-- Loading skeleton --%>
        <%= if @loading do %>
          <div class="mb-6">
            <div class="rounded-xl border border-base-300/50 bg-base-200/30 p-5 animate-pulse">
              <div class="h-4 bg-base-300/60 rounded-lg w-1/3 mb-3"></div>
              <div class="h-3 bg-base-300/40 rounded-lg w-1/2 mb-5"></div>
              <div class="h-36 bg-base-300/30 rounded-lg"></div>
            </div>
          </div>
        <% end %>

        <%!-- Results Grid --%>
        <div
          id="results"
          phx-update="stream"
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
        >
          <%!-- Empty state: visible only when no stream items exist --%>
          <div id="empty-state" class="hidden only:block col-span-full text-center py-24">
            <div class="text-base-content/20 mb-6">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-20 mx-auto">
                <path d="M18.375 2.25c-1.035 0-1.875.84-1.875 1.875v15.75c0 1.035.84 1.875 1.875 1.875h.75c1.035 0 1.875-.84 1.875-1.875V4.125c0-1.035-.84-1.875-1.875-1.875h-.75ZM9.75 8.625c0-1.036.84-1.875 1.875-1.875h.75c1.036 0 1.875.84 1.875 1.875v11.25c0 1.035-.84 1.875-1.875 1.875h-.75a1.875 1.875 0 0 1-1.875-1.875V8.625ZM3 13.125c0-1.036.84-1.875 1.875-1.875h.75c1.036 0 1.875.84 1.875 1.875v6.75c0 1.035-.84 1.875-1.875 1.875h-.75A1.875 1.875 0 0 1 3 19.875v-6.75Z" />
              </svg>
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
      </div>
    </Dai.Layouts.app>
    """
  end

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
