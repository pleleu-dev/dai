defmodule Dai.SidebarComponents do
  @moduledoc "Function components for the folder panel and save actions."

  use Phoenix.Component

  alias Dai.Icons
  alias Phoenix.LiveView.JS

  # --- Folder panel (new two-panel layout) ---

  attr :folders, :list, required: true
  attr :active_folder_id, :string, default: nil
  attr :folder_queries, :list, default: []

  def folder_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex items-center justify-between px-4 py-3 shrink-0 border-b border-base-300">
        <div class="flex items-center gap-2">
          <Icons.folder class="size-4 text-base-content/60" />
          <span class="text-sm font-semibold">Folders</span>
        </div>
        <button
          phx-click={toggle_dropdown("new-folder-input")}
          class="btn btn-ghost btn-xs btn-square"
          aria-label="Create folder"
        >
          <Icons.plus class="size-3.5" />
        </button>
      </div>
      <div id="new-folder-input" class="hidden px-3 py-2 border-b border-base-300">
        <form phx-submit="create_folder" class="flex gap-1">
          <input
            type="text"
            name="name"
            placeholder="Folder name"
            class="input input-xs input-bordered flex-1"
            phx-click-away={hide_dropdown("new-folder-input")}
          />
          <button type="submit" class="btn btn-primary btn-xs">Add</button>
        </form>
      </div>
      <div class="flex-1 overflow-y-auto px-2 py-1">
        <.expanded_folder_list
          folders={@folders}
          active_folder_id={@active_folder_id}
          folder_queries={@folder_queries}
        />
      </div>
    </div>
    """
  end

  # --- Legacy sidebar (kept temporarily for backward compatibility) ---

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
        class="btn btn-ghost btn-xs btn-square text-base-content/60 hover:bg-primary/10 hover:text-primary"
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
            class="hidden flex-1 min-w-0 ml-5"
            phx-submit={
              JS.push("rename_folder", value: %{id: folder.id})
              |> cancel_rename(folder.id)
            }
            phx-click-away={cancel_rename(folder.id)}
          >
            <input
              id={"folder-rename-input-#{folder.id}"}
              type="text"
              name="name"
              value={if(folder.name == Dai.Folders.default_folder_name(), do: "", else: folder.name)}
              placeholder="Folder name..."
              class="w-full text-xs bg-transparent border-b border-base-content/20 px-0 py-0.5 outline-none focus:border-primary transition-colors"
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
            <ul
              id={"folder-menu-#{folder.id}"}
              class="hidden absolute right-0 top-6 z-30 menu menu-xs bg-base-100 border border-base-300 rounded-box w-36 p-1 shadow-sm"
              phx-click-away={hide_dropdown("folder-menu-#{folder.id}")}
            >
              <li>
                <button phx-click={start_rename(folder.id)}>
                  <Icons.pencil class="size-3" /> Rename
                </button>
              </li>
              <li>
                <button phx-click={
                  JS.push("load_all_folder_queries", value: %{id: folder.id})
                  |> hide_dropdown("folder-menu-#{folder.id}")
                }>
                  <Icons.play class="size-3" /> Run all queries
                </button>
              </li>
              <li class="border-t border-base-300 mt-1 pt-1">
                <button
                  class="text-error"
                  phx-click={
                    JS.push("delete_folder", value: %{id: folder.id})
                    |> hide_dropdown("folder-menu-#{folder.id}")
                  }
                >
                  <Icons.trash class="size-3" /> Delete
                </button>
              </li>
            </ul>
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
      <ul
        id={@dropdown_id}
        class="hidden absolute right-0 top-8 z-20 menu menu-xs bg-base-100 border border-base-300 rounded-box w-48 p-1 shadow-sm"
        phx-click-away={hide_dropdown(@dropdown_id)}
      >
        <li :for={folder <- @folders}>
          <button
            phx-click={JS.push("save_query") |> hide_dropdown(@dropdown_id)}
            phx-value-folder-id={folder.id}
            phx-value-prompt={@prompt}
            phx-value-title={@title}
          >
            <Icons.folder class="size-3" />
            <span class="truncate">{folder.name}</span>
          </button>
        </li>
        <li :if={@folders != []} class="border-t border-base-300 mt-1 pt-1"></li>
        <li>
          <button
            class="text-primary"
            phx-click={JS.push("save_query_new_folder") |> hide_dropdown(@dropdown_id)}
            phx-value-prompt={@prompt}
            phx-value-title={@title}
          >
            <Icons.plus class="size-3" />
            <span>New folder...</span>
          </button>
        </li>
      </ul>
    </div>
    """
  end

  defp toggle_dropdown(id) do
    JS.toggle(
      to: "##{id}",
      in: {"ease-out duration-100", "opacity-0 scale-95", "opacity-100 scale-100"},
      out: {"ease-in duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
  end

  defp hide_dropdown(%Phoenix.LiveView.JS{} = js, id) do
    JS.hide(js,
      to: "##{id}",
      transition: {"ease-in duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
  end

  defp hide_dropdown(id) do
    JS.hide(
      to: "##{id}",
      transition: {"ease-in duration-75", "opacity-100 scale-100", "opacity-0 scale-95"}
    )
  end

  defp start_rename(folder_id) do
    JS.hide(to: "#folder-menu-#{folder_id}")
    |> JS.hide(to: "#folder-row-#{folder_id}")
    |> JS.hide(to: "#folder-actions-#{folder_id}")
    |> JS.show(to: "#folder-rename-#{folder_id}")
    |> JS.focus(to: "#folder-rename-input-#{folder_id}")
  end

  defp cancel_rename(%Phoenix.LiveView.JS{} = js, folder_id) do
    js
    |> JS.hide(to: "#folder-rename-#{folder_id}")
    |> JS.show(to: "#folder-row-#{folder_id}", display: "flex")
    |> JS.show(to: "#folder-actions-#{folder_id}")
  end

  defp cancel_rename(folder_id) do
    JS.hide(to: "#folder-rename-#{folder_id}")
    |> JS.show(to: "#folder-row-#{folder_id}", display: "flex")
    |> JS.show(to: "#folder-actions-#{folder_id}")
  end
end
