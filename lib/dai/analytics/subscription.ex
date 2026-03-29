defmodule Dai.Analytics.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscriptions" do
    field :status, :string, default: "active"
    field :started_at, :utc_datetime
    field :cancelled_at, :utc_datetime

    belongs_to :user, Dai.Analytics.User
    belongs_to :plan, Dai.Analytics.Plan
    has_many :invoices, Dai.Analytics.Invoice

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:status, :started_at, :cancelled_at])
    |> validate_required([:status, :started_at])
  end
end
