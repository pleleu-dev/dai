defmodule Dai.SidebarComponents do
  @moduledoc "Function components for the collapsible folder sidebar."

  use Phoenix.Component

  alias Dai.Icons

  attr :sidebar_open, :boolean, required: true
  attr :folders, :list, required: true
  attr :active_folder_id, :string, default: nil
  attr :folder_queries, :list, default: []

  def sidebar(assigns) do
    ~H"""
    <aside class={[
      "shrink-0 border-r border-base-300 bg-base-200/30 transition-all duration-200 overflow-hidden flex flex-col",
      @sidebar_open && "w-56",
      !@sidebar_open && "w-11"
    ]}>
      <div class={[
        "flex items-center gap-2 p-2 border-b border-base-300",
        @sidebar_open && "justify-between",
        !@sidebar_open && "justify-center"
      ]}>
        <button
          phx-click="toggle_sidebar"
          class="btn btn-ghost btn-xs btn-circle"
          aria-label="Toggle sidebar"
        >
          <Icons.bars_3 class="size-4" />
        </button>
        <span
          :if={@sidebar_open}
          class="text-xs font-semibold text-base-content/70 uppercase tracking-wider"
        >
          Folders
        </span>
        <button
          :if={@sidebar_open}
          phx-click="create_folder"
          class="btn btn-ghost btn-xs btn-circle text-primary"
          aria-label="New folder"
        >
          <Icons.plus class="size-4" />
        </button>
      </div>

      <%= if @sidebar_open do %>
        <.expanded_folder_list
          folders={@folders}
          active_folder_id={@active_folder_id}
          folder_queries={@folder_queries}
        />
      <% else %>
        <.collapsed_folder_list folders={@folders} />
      <% end %>
    </aside>
    """
  end

  attr :folders, :list, required: true

  defp collapsed_folder_list(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1 p-1 overflow-y-auto">
      <button
        :for={folder <- @folders}
        phx-click="load_folder"
        phx-value-id={folder.id}
        class="w-7 h-7 rounded-md bg-base-300/50 flex items-center justify-center text-xs font-medium text-base-content/60 hover:bg-primary/10 hover:text-primary transition-colors"
        title={folder.name}
      >
        {String.first(folder.name)}
      </button>
    </div>
    """
  end

  attr :folders, :list, required: true
  attr :active_folder_id, :string, default: nil
  attr :folder_queries, :list, default: []

  defp expanded_folder_list(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto p-2">
      <div :if={@folders == []} class="text-xs text-base-content/30 text-center py-4">
        No folders yet
      </div>
      <div :for={folder <- @folders} class="mb-1">
        <%!-- Folder row: click to open, ... menu for actions --%>
        <div class={[
          "flex items-center gap-1 px-2 py-1.5 rounded-md text-sm group transition-colors",
          folder.id == @active_folder_id && "bg-primary/10 text-primary",
          folder.id != @active_folder_id && "text-base-content/60 hover:bg-base-300/50"
        ]}>
          <%!-- Normal row (visible by default) --%>
          <button
            id={"folder-row-#{folder.id}"}
            phx-click="load_folder"
            phx-value-id={folder.id}
            class="flex items-center gap-1.5 flex-1 min-w-0"
          >
            <Icons.chevron_right class={[
              "size-3 shrink-0 transition-transform",
              folder.id == @active_folder_id && "rotate-90"
            ]} />
            <Icons.folder class="size-4 shrink-0" />
            <span class="truncate text-xs">{folder.name}</span>
          </button>

          <%!-- Inline rename form (hidden by default, replaces entire row) --%>
          <form
            id={"folder-rename-#{folder.id}"}
            class="hidden flex-1 min-w-0"
            phx-submit={
              Phoenix.LiveView.JS.push("rename_folder", value: %{id: folder.id})
              |> cancel_rename(folder.id)
            }
            phx-click-away={cancel_rename(folder.id)}
          >
            <input
              id={"folder-rename-input-#{folder.id}"}
              type="text"
              name="name"
              value={if(folder.name == "New Folder", do: "", else: folder.name)}
              placeholder="Folder name..."
              class="input input-xs w-full"
              phx-keydown={cancel_rename(folder.id)}
              phx-key="Escape"
            />
          </form>

          <%!-- Action menu trigger (hidden during rename) --%>
          <div id={"folder-actions-#{folder.id}"} class="relative">
            <button
              phx-click={toggle_dropdown("folder-menu-#{folder.id}")}
              class="opacity-0 group-hover:opacity-60 hover:!opacity-100 transition-opacity p-0.5 rounded hover:bg-base-300/50"
              aria-label="Folder actions"
            >
              <Icons.ellipsis_vertical class="size-3.5" />
            </button>
            <%!-- Dropdown menu --%>
            <div
              id={"folder-menu-#{folder.id}"}
              class="hidden absolute right-0 top-6 z-30 w-36 bg-base-100 border border-base-300 rounded-lg shadow-lg py-1"
              phx-click-away={hide_dropdown("folder-menu-#{folder.id}")}
            >
              <button
                phx-click={start_rename(folder.id)}
                class="w-full text-left px-3 py-1.5 text-xs text-base-content/70 hover:bg-base-200 flex items-center gap-2"
              >
                <Icons.pencil class="size-3 shrink-0" />
                <span>Rename</span>
              </button>
              <button
                phx-click={
                  Phoenix.LiveView.JS.push("load_all_folder_queries", value: %{id: folder.id})
                  |> hide_dropdown("folder-menu-#{folder.id}")
                }
                class="w-full text-left px-3 py-1.5 text-xs text-base-content/70 hover:bg-base-200 flex items-center gap-2"
              >
                <Icons.play class="size-3 shrink-0" />
                <span>Run all queries</span>
              </button>
              <div class="border-t border-base-300 my-1"></div>
              <button
                phx-click={
                  Phoenix.LiveView.JS.push("delete_folder", value: %{id: folder.id})
                  |> hide_dropdown("folder-menu-#{folder.id}")
                }
                class="w-full text-left px-3 py-1.5 text-xs text-error hover:bg-base-200 flex items-center gap-2"
              >
                <Icons.trash class="size-3 shrink-0" />
                <span>Delete</span>
              </button>
            </div>
          </div>
        </div>
        <.folder_query_list
          :if={folder.id == @active_folder_id}
          queries={@folder_queries}
        />
      </div>
    </div>
    """
  end

  attr :queries, :list, required: true

  defp folder_query_list(assigns) do
    ~H"""
    <div class="ml-6 mt-0.5 mb-1">
      <div :if={@queries == []} class="text-xs text-base-content/30 py-1 px-2">
        No saved queries
      </div>
      <div
        :for={query <- @queries}
        class="flex items-center gap-1 px-2 py-1 rounded group hover:bg-base-300/30 transition-colors"
      >
        <button
          phx-click="run_saved_query"
          phx-value-id={query.id}
          phx-value-prompt={query.prompt}
          class="flex-1 min-w-0 text-left"
        >
          <span class="text-xs text-base-content/50 hover:text-base-content/80 truncate block">
            {query.title}
          </span>
        </button>
        <button
          phx-click="delete_saved_query"
          phx-value-id={query.id}
          class="opacity-0 group-hover:opacity-60 hover:!opacity-100 text-error transition-opacity shrink-0"
          title="Remove query"
        >
          <Icons.x_mark class="size-3" />
        </button>
      </div>
    </div>
    """
  end

  # --- Save dropdown (shown on result cards) ---

  attr :result_id, :string, required: true
  attr :prompt, :string, required: true
  attr :title, :string, default: nil
  attr :folders, :list, required: true

  def save_button(assigns) do
    dropdown_id = "save-dropdown-#{assigns.result_id}"
    assigns = assign(assigns, :dropdown_id, dropdown_id)

    ~H"""
    <div class="relative">
      <button
        phx-click={toggle_dropdown(@dropdown_id)}
        class="btn btn-ghost btn-xs btn-circle opacity-50 hover:opacity-100"
        aria-label="Save query"
      >
        <Icons.bookmark class="size-4" />
      </button>
      <div
        id={@dropdown_id}
        class="hidden absolute right-0 top-8 z-20 w-48 bg-base-100 border border-base-300 rounded-lg shadow-lg py-1"
        phx-click-away={hide_dropdown(@dropdown_id)}
      >
        <button
          :for={folder <- @folders}
          phx-click={Phoenix.LiveView.JS.push("save_query") |> hide_dropdown(@dropdown_id)}
          phx-value-folder-id={folder.id}
          phx-value-prompt={@prompt}
          phx-value-title={@title}
          class="w-full text-left px-3 py-1.5 text-xs text-base-content/70 hover:bg-base-200 flex items-center gap-2"
        >
          <Icons.folder class="size-3 shrink-0" />
          <span class="truncate">{folder.name}</span>
        </button>
        <div :if={@folders != []} class="border-t border-base-300 my-1"></div>
        <button
          phx-click={Phoenix.LiveView.JS.push("save_query_new_folder") |> hide_dropdown(@dropdown_id)}
          phx-value-prompt={@prompt}
          phx-value-title={@title}
          class="w-full text-left px-3 py-1.5 text-xs text-primary hover:bg-base-200 flex items-center gap-2"
        >
          <Icons.plus class="size-3 shrink-0" />
          <span>New folder...</span>
        </button>
      </div>
    </div>
    """
  end

  defp toggle_dropdown(id) do
    Phoenix.LiveView.JS.toggle(to: "##{id}", in: {"ease-out duration-100", "opacity-0 scale-95", "opacity-100 scale-100"}, out: {"ease-in duration-75", "opacity-100 scale-100", "opacity-0 scale-95"})
  end

  defp hide_dropdown(%Phoenix.LiveView.JS{} = js, id) do
    Phoenix.LiveView.JS.hide(js, to: "##{id}", transition: {"ease-in duration-75", "opacity-100 scale-100", "opacity-0 scale-95"})
  end

  defp hide_dropdown(id) do
    Phoenix.LiveView.JS.hide(to: "##{id}", transition: {"ease-in duration-75", "opacity-100 scale-100", "opacity-0 scale-95"})
  end

  defp start_rename(folder_id) do
    Phoenix.LiveView.JS.hide(to: "#folder-menu-#{folder_id}")
    |> Phoenix.LiveView.JS.hide(to: "#folder-row-#{folder_id}")
    |> Phoenix.LiveView.JS.hide(to: "#folder-actions-#{folder_id}")
    |> Phoenix.LiveView.JS.show(to: "#folder-rename-#{folder_id}")
    |> Phoenix.LiveView.JS.focus(to: "#folder-rename-input-#{folder_id}")
  end

  defp cancel_rename(%Phoenix.LiveView.JS{} = js, folder_id) do
    js
    |> Phoenix.LiveView.JS.hide(to: "#folder-rename-#{folder_id}")
    |> Phoenix.LiveView.JS.show(to: "#folder-row-#{folder_id}")
    |> Phoenix.LiveView.JS.show(to: "#folder-actions-#{folder_id}")
  end

  defp cancel_rename(folder_id) do
    Phoenix.LiveView.JS.hide(to: "#folder-rename-#{folder_id}")
    |> Phoenix.LiveView.JS.show(to: "#folder-row-#{folder_id}")
    |> Phoenix.LiveView.JS.show(to: "#folder-actions-#{folder_id}")
  end
end
