defmodule Dai.Folders do
  @moduledoc """
  Context for managing saved query folders.

  Every public function is scoped to a `user_token` (the tenant identity carried
  by the LiveView socket). Reads filter by `user_token`; ownership-sensitive
  writes look the row up with `get_by(id:, user_token:)` and return
  `{:error, :not_found}` when the caller does not own it — closing the IDOR where
  any visitor could rename or delete another visitor's folders and queries.
  """

  import Ecto.Query

  alias Dai.Folders.{Folder, SavedQuery}

  @default_folder_name "New Folder"

  defp repo, do: Dai.Config.repo()

  def default_folder_name, do: @default_folder_name

  # --- Folders ---

  def list_folders(user_token) do
    Folder
    |> where(user_token: ^user_token)
    |> order_by(:position)
    |> repo().all()
  end

  def get_folder!(user_token, id), do: repo().get_by!(Folder, id: id, user_token: user_token)

  def create_folder(user_token, attrs) do
    %Folder{}
    |> Folder.changeset(Map.put(attrs, :user_token, user_token))
    |> repo().insert()
  end

  def update_folder(%Folder{} = folder, attrs) do
    folder
    |> Folder.update_changeset(attrs)
    |> repo().update()
  end

  def delete_folder(%Folder{} = folder) do
    repo().delete(folder)
  end

  def rename_folder(user_token, id, name) do
    with {:ok, folder} <- fetch_owned(Folder, user_token, id),
         do: update_folder(folder, %{name: name})
  end

  def delete_folder_by_id(user_token, id) do
    with {:ok, folder} <- fetch_owned(Folder, user_token, id),
         do: repo().delete(folder)
  end

  # --- Saved Queries ---

  def list_saved_queries(user_token, folder_id) do
    SavedQuery
    |> where(user_token: ^user_token, folder_id: ^folder_id)
    |> order_by(:position)
    |> repo().all()
  end

  def get_saved_query!(user_token, id),
    do: repo().get_by!(SavedQuery, id: id, user_token: user_token)

  def create_saved_query(user_token, attrs) do
    # The target folder must belong to the caller — otherwise a client could
    # stamp a saved query against another tenant's folder_id.
    with {:ok, _folder} <- fetch_owned(Folder, user_token, Map.get(attrs, :folder_id)) do
      %SavedQuery{}
      |> SavedQuery.changeset(Map.put(attrs, :user_token, user_token))
      |> repo().insert()
    end
  end

  def save_query_to_new_folder(user_token, prompt, title, position) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :folder,
      Folder.changeset(%Folder{}, %{
        user_token: user_token,
        name: @default_folder_name,
        position: position
      })
    )
    |> Ecto.Multi.insert(:query, fn %{folder: folder} ->
      SavedQuery.changeset(%SavedQuery{}, %{
        user_token: user_token,
        folder_id: folder.id,
        prompt: prompt,
        title: title
      })
    end)
    |> repo().transaction()
  end

  def update_saved_query(%SavedQuery{} = query, attrs) do
    query
    |> SavedQuery.update_changeset(attrs)
    |> repo().update()
  end

  def delete_saved_query_by_id(user_token, id) do
    with {:ok, query} <- fetch_owned(SavedQuery, user_token, id),
         do: repo().delete(query)
  end

  def delete_saved_query(%SavedQuery{} = query) do
    repo().delete(query)
  end

  def rename_saved_query(user_token, id, title) do
    with {:ok, query} <- fetch_owned(SavedQuery, user_token, id),
         do: update_saved_query(query, %{title: title})
  end

  # Single source of truth for the tenant-ownership boundary: a row is only
  # returned to a caller that owns it; otherwise `{:error, :not_found}`.
  defp fetch_owned(schema, user_token, id) do
    case repo().get_by(schema, id: id, user_token: user_token) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end
end
