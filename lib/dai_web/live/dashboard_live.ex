defmodule DaiWeb.DashboardLive do
  use DaiWeb, :live_view

  alias Dai.AI.{QueryPipeline, Result}
  alias Dai.SchemaContext

  import DaiWeb.DashboardComponents

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
