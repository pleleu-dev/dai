defmodule Dai.Analytics.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :name, :string
    field :properties, :map, default: %{}

    belongs_to :user, Dai.Analytics.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:name, :properties])
    |> validate_required([:name])
  end
end
