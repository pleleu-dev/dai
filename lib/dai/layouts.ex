defmodule Dai.Layouts do
  @moduledoc "Layout components for the Dai dashboard."
  use Phoenix.Component

  alias Dai.Icons

  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="dai-dashboard h-screen flex flex-col">
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300 shrink-0">
        <div class="flex-1">
          <span class="flex items-center gap-2">
            <Icons.chart_bar class="size-6 text-primary" />
            <span class="text-lg font-bold text-base-content">Dai</span>
          </span>
        </div>
      </header>
      <main class="flex-1 min-h-0">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end
end
