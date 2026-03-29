defmodule Dai.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    create table(:plans) do
      add :name, :string, null: false
      add :price_monthly, :integer, null: false, default: 0
      add :tier, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plans, [:tier])
  end
end
