defmodule Dai.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :properties, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:events, [:user_id])
    create index(:events, [:name])
    create index(:events, [:inserted_at])
  end
end
