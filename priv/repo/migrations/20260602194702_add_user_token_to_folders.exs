defmodule Dai.Repo.Migrations.AddUserTokenToFolders do
  use Ecto.Migration

  # Adds tenant ownership (`user_token`) to folders and saved queries, closing
  # the IDOR where any visitor could list/rename/delete another visitor's data.
  # Existing demo rows (if any) are backfilled with a sentinel before the
  # NOT NULL constraint is applied; the column add + modify are reversible.
  def change do
    alter table(:dai_folders) do
      add :user_token, :string
    end

    alter table(:dai_saved_queries) do
      add :user_token, :string
    end

    execute(
      "UPDATE dai_folders SET user_token = 'legacy' WHERE user_token IS NULL",
      "SELECT 1"
    )

    execute(
      "UPDATE dai_saved_queries SET user_token = 'legacy' WHERE user_token IS NULL",
      "SELECT 1"
    )

    alter table(:dai_folders) do
      modify :user_token, :string, null: false, from: {:string, null: true}
    end

    alter table(:dai_saved_queries) do
      modify :user_token, :string, null: false, from: {:string, null: true}
    end

    create index(:dai_folders, [:user_token])
    create index(:dai_saved_queries, [:user_token])
    create index(:dai_folders, [:position])
  end
end
