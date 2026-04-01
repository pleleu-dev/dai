defmodule Dai.Folders do
  @moduledoc "Context for managing saved query folders."

  import Ecto.Query

  alias Dai.Folders.{Folder, SavedQuery}

  @default_folder_name "New Folder"

  defp repo, do: Dai.Config.repo()

  def default_folder_name, do: @default_folder_name

  # --- Folders ---

  def list_folders do
    Folder
    |> order_by(:position)
    |> repo().all()
  end

  def get_folder!(id), do: repo().get!(Folder, id)

  def create_folder(attrs) do
    %Folder{}
    |> Folder.changeset(attrs)
    |> repo().insert()
  end

  def update_folder(%Folder{} = folder, attrs) do
    folder
    |> Folder.changeset(attrs)
    |> repo().update()
  end

  def delete_folder(%Folder{} = folder) do
    repo().delete(folder)
  end

  def rename_folder(id, name) do
    case repo().get(Folder, id) do
      nil -> {:error, :not_found}
      folder -> update_folder(folder, %{name: name})
    end
  end

  def delete_folder_by_id(id) do
    case repo().get(Folder, id) do
      nil -> {:error, :not_found}
      folder -> repo().delete(folder)
    end
  end

  # --- Saved Queries ---

  def list_saved_queries(folder_id) do
    SavedQuery
    |> where(folder_id: ^folder_id)
    |> order_by(:position)
    |> repo().all()
  end

  def get_saved_query!(id), do: repo().get!(SavedQuery, id)

  def create_saved_query(attrs) do
    %SavedQuery{}
    |> SavedQuery.changeset(attrs)
    |> repo().insert()
  end

  def save_query_to_new_folder(prompt, title, position) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :folder,
      Folder.changeset(%Folder{}, %{name: @default_folder_name, position: position})
    )
    |> Ecto.Multi.insert(:query, fn %{folder: folder} ->
      SavedQuery.changeset(%SavedQuery{}, %{folder_id: folder.id, prompt: prompt, title: title})
    end)
    |> repo().transaction()
  end

  def update_saved_query(%SavedQuery{} = query, attrs) do
    query
    |> SavedQuery.changeset(attrs)
    |> repo().update()
  end

  def delete_saved_query_by_id(id) do
    case repo().get(SavedQuery, id) do
      nil -> {:error, :not_found}
      query -> repo().delete(query)
    end
  end

  def delete_saved_query(%SavedQuery{} = query) do
    repo().delete(query)
  end

  def rename_saved_query(id, title) do
    case repo().get(SavedQuery, id) do
      nil -> {:error, :not_found}
      query -> update_saved_query(query, %{title: title})
    end
  end
end
