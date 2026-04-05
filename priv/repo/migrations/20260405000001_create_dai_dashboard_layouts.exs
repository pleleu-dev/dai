defmodule Dai.Repo.Migrations.CreateDaiDashboardLayouts do
  use Ecto.Migration

  def change do
    create table(:dai_dashboard_layouts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_token, :string, null: false
      add :layout_key, :string, null: false
      add :x, :integer, null: false, default: 0
      add :y, :integer, null: false, default: 0
      add :w, :integer, null: false
      add :h, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:dai_dashboard_layouts, [:user_token, :layout_key])
    create index(:dai_dashboard_layouts, [:user_token])
  end
end
