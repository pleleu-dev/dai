defmodule Dai.Folders.Folder do
  use Ecto.Schema
  import Ecto.Changeset

  alias Dai.Folders.SavedQuery

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "dai_folders" do
    field :user_token, :string
    field :name, :string
    field :position, :integer

    has_many :saved_queries, SavedQuery

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:user_token, :name, :position])
    |> validate_required([:user_token, :name])
  end

  @doc "Update changeset — deliberately excludes `:user_token` so ownership can't be reassigned."
  def update_changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name, :position])
    |> validate_required([:name])
  end
end
