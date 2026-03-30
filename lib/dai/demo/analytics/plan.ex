defmodule Dai.Demo.Analytics.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  schema "plans" do
    field :name, :string
    field :price_monthly, :integer, default: 0
    field :tier, :string

    has_many :subscriptions, Dai.Demo.Analytics.Subscription
    has_many :features, Dai.Demo.Analytics.Feature

    timestamps(type: :utc_datetime)
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:name, :price_monthly, :tier])
    |> validate_required([:name, :price_monthly, :tier])
    |> unique_constraint(:tier)
  end
end
