defmodule Dai.Analytics.Feature do
  use Ecto.Schema
  import Ecto.Changeset

  schema "features" do
    field :name, :string
    field :enabled, :boolean, default: true

    belongs_to :plan, Dai.Analytics.Plan

    timestamps(type: :utc_datetime)
  end

  def changeset(feature, attrs) do
    feature
    |> cast(attrs, [:name, :enabled])
    |> validate_required([:name])
  end
end
