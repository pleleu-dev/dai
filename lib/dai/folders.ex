defmodule Dai.Folders do
  @moduledoc "Context for managing saved query folders."

  import Ecto.Query

  alias Dai.Folders.{Folder, SavedQuery}

  defp repo, do: Dai.Config.repo()

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

  def update_saved_query(%SavedQuery{} = query, attrs) do
    query
    |> SavedQuery.changeset(attrs)
    |> repo().update()
  end

  def delete_saved_query(%SavedQuery{} = query) do
    repo().delete(query)
  end
end
