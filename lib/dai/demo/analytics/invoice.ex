defmodule Dai.Demo.Analytics.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invoices" do
    field :amount_cents, :integer
    field :status, :string, default: "pending"
    field :due_date, :date
    field :paid_at, :utc_datetime

    belongs_to :subscription, Dai.Demo.Analytics.Subscription

    timestamps(type: :utc_datetime)
  end

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [:amount_cents, :status, :due_date, :paid_at])
    |> validate_required([:amount_cents, :status, :due_date])
  end
end
