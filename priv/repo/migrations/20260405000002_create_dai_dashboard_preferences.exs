defmodule Dai.Repo.Migrations.CreateDaiDashboardPreferences do
  use Ecto.Migration

  def change do
    create table(:dai_dashboard_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_token, :string, null: false
      add :panel_sizes, :map, default: %{"main_split" => 75, "right_split" => 50}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:dai_dashboard_preferences, [:user_token])
  end
end
