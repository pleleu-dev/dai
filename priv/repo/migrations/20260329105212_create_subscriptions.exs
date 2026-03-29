defmodule Dai.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :plan_id, references(:plans, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "active"
      add :started_at, :utc_datetime, null: false
      add :cancelled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:subscriptions, [:user_id])
    create index(:subscriptions, [:plan_id])
    create index(:subscriptions, [:status])
  end
end
