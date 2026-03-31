defmodule Dai.Repo.Migrations.CreateDaiFolders do
  use Ecto.Migration

  def change do
    create table(:dai_folders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :position, :integer

      timestamps(type: :utc_datetime)
    end
  end
end
