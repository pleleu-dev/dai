defmodule Dai.Folders.SavedQuery do
  use Ecto.Schema
  import Ecto.Changeset

  alias Dai.Folders.Folder

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "dai_saved_queries" do
    field :prompt, :string
    field :title, :string
    field :position, :integer

    belongs_to :folder, Folder

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(saved_query, attrs) do
    saved_query
    |> cast(attrs, [:prompt, :title, :position, :folder_id])
    |> validate_required([:prompt, :folder_id])
    |> foreign_key_constraint(:folder_id)
    |> set_default_title()
  end

  defp set_default_title(changeset) do
    case get_field(changeset, :title) do
      nil -> put_change(changeset, :title, truncate_prompt(get_field(changeset, :prompt)))
      "" -> put_change(changeset, :title, truncate_prompt(get_field(changeset, :prompt)))
      _ -> changeset
    end
  end

  defp truncate_prompt(nil), do: "Untitled"
  defp truncate_prompt(prompt) when byte_size(prompt) <= 60, do: prompt
  defp truncate_prompt(prompt), do: String.slice(prompt, 0, 57) <> "..."
end
