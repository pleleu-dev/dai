defmodule Dai.GridBridge do
  @moduledoc """
  Bridges LiveView with the GridStack JS hook.

  Handles server-side card rendering, push events for adding/removing
  cards, and layout/panel persistence. DashboardLive delegates all
  grid concerns to this module.
  """

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]

  alias Dai.{DashboardLayout, DashboardPreferences}
  alias Dai.AI.Result

  @doc "Render a result card to HTML and push it to the GridStack hook."
  def push_card(socket, card) do
    assigns = %{result: card, folders: socket.assigns.folders}

    html =
      Dai.DashboardComponents.result_card(assigns)
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    push_event(socket, "add_card", %{
      id: card.id,
      html: html,
      layout_key: card.layout_key,
      card_type: to_string(card.type)
    })
  end

  @doc "Push a remove_card event to the GridStack hook."
  def remove_card(socket, id) do
    push_event(socket, "remove_card", %{id: id})
  end

  @doc "Convert a pipeline result tuple to a Result with layout_key."
  def result_to_card({:ok, result}, _prompt) do
    %{result | layout_key: DashboardLayout.layout_key(result.prompt)}
  end

  def result_to_card({:error, reason}, prompt) do
    error = Result.error(reason, prompt)
    %{error | layout_key: DashboardLayout.layout_key(prompt)}
  end

  @doc "Persist card layout positions from a GridStack change event."
  def save_layouts(socket, cards) do
    DashboardLayout.save_layouts(socket.assigns.user_token, cards)
    socket
  end

  @doc "Persist panel sizes from a resizer drag event."
  def save_panel_sizes(socket, name, size) do
    panel_sizes = Map.put(socket.assigns.panel_sizes, name, size)
    DashboardPreferences.save_panel_sizes(socket.assigns.user_token, panel_sizes)
    assign(socket, panel_sizes: panel_sizes)
  end
end
