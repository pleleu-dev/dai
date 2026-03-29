defmodule Dai.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices) do
      add :subscription_id, references(:subscriptions, on_delete: :delete_all), null: false
      add :amount_cents, :integer, null: false
      add :status, :string, null: false, default: "pending"
      add :due_date, :date, null: false
      add :paid_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:invoices, [:subscription_id])
    create index(:invoices, [:status])
    create index(:invoices, [:due_date])
  end
end
