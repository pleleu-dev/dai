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

          <%!-- Inline actions (visible on hover) --%>
          <div id={"folder-actions-#{folder.id}"} class="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity shrink-0">
            <button
              phx-click={start_rename(folder.id)}
              class="p-0.5 rounded text-base-content/40 hover:text-base-content/80 hover:bg-base-300/50"
              aria-label="Rename folder"
              title="Rename"
            >
              <Icons.pencil class="size-3" />
            </button>
            <button
              phx-click={JS.push("load_all_folder_queries", value: %{id: folder.id})}
              class="p-0.5 rounded text-base-content/40 hover:text-primary hover:bg-primary/10"
              aria-label="Run all queries"
              title="Run all"
            >
              <Icons.play class="size-3" />
            </button>
            <button
              phx-click={JS.push("delete_folder", value: %{id: folder.id})}
              class="p-0.5 rounded text-base-content/40 hover:text-error hover:bg-error/10"
              aria-label="Delete folder"
              title="Delete"
            >
              <Icons.trash class="size-3" />
            </button>
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
