defmodule Dai.Demo.Analytics.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscriptions" do
    field :status, :string, default: "active"
    field :started_at, :utc_datetime
    field :cancelled_at, :utc_datetime

    belongs_to :user, Dai.Demo.Analytics.User
    belongs_to :plan, Dai.Demo.Analytics.Plan
    has_many :invoices, Dai.Demo.Analytics.Invoice

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:status, :started_at, :cancelled_at])
    |> validate_required([:status, :started_at])
  end
end
