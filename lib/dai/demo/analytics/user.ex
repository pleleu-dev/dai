defmodule Dai.Demo.Analytics.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :role, :string, default: "member"
    field :org_name, :string

    has_many :subscriptions, Dai.Demo.Analytics.Subscription
    has_many :events, Dai.Demo.Analytics.Event

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role, :org_name])
    |> validate_required([:name, :email, :role, :org_name])
    |> unique_constraint(:email)
  end
end
