defmodule Dai.Repo.Migrations.CreateDaiSavedQueries do
  use Ecto.Migration

  def change do
    create table(:dai_saved_queries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :folder_id, references(:dai_folders, type: :binary_id, on_delete: :delete_all),
        null: false
      add :prompt, :text, null: false
      add :title, :string
      add :position, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:dai_saved_queries, [:folder_id])
  end
end
