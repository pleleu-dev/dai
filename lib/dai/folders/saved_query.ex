defmodule Dai.Folders.SavedQuery do
  use Ecto.Schema
  import Ecto.Changeset

  alias Dai.Folders.Folder

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "dai_saved_queries" do
    field :user_token, :string
    field :prompt, :string
    field :title, :string
    field :position, :integer

    belongs_to :folder, Folder

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(saved_query, attrs) do
    saved_query
    |> cast(attrs, [:user_token, :prompt, :title, :position, :folder_id])
    |> validate_required([:user_token, :prompt, :folder_id])
    |> foreign_key_constraint(:folder_id)
    |> set_default_title()
  end

  @doc "Update changeset — excludes `:user_token` and `:folder_id` so neither ownership nor parent can be reassigned."
  def update_changeset(saved_query, attrs) do
    saved_query
    |> cast(attrs, [:title, :position])
    |> set_default_title()
  end

  defp set_default_title(changeset) do
    if get_field(changeset, :title) in [nil, ""] do
      put_change(changeset, :title, truncate_prompt(get_field(changeset, :prompt)))
    else
      changeset
    end
  end

  defp truncate_prompt(nil), do: "Untitled"
  defp truncate_prompt(prompt) when byte_size(prompt) <= 60, do: prompt
  defp truncate_prompt(prompt), do: String.slice(prompt, 0, 57) <> "..."
end
