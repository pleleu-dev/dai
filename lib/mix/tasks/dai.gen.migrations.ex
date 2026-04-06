defmodule Mix.Tasks.Dai.Gen.Migrations do
  @shortdoc "Generates Dai dashboard migrations"
  @moduledoc """
  Generates Ecto migration files for Dai dashboard tables.

      $ mix dai.gen.migrations

  This creates migration files for:
  - `dai_folders` — saved query folders
  - `dai_saved_queries` — saved queries within folders
  - `dai_dashboard_layouts` — card grid positions
  - `dai_dashboard_preferences` — panel sizes and preferences
  """

  use Mix.Task

  import Mix.Generator

  @migrations ~w(create_dai_folders create_dai_saved_queries create_dai_dashboard_layouts create_dai_dashboard_preferences)

  @impl true
  def run(_args) do
    migrations_path = Path.join(["priv", "repo", "migrations"])
    File.mkdir_p!(migrations_path)

    existing = File.ls!(migrations_path)

    for {name, index} <- Enum.with_index(@migrations) do
      if Enum.any?(existing, &String.contains?(&1, name)) do
        Mix.shell().info("Migration #{name} already exists, skipping.")
      else
        timestamp = generate_timestamp(index)
        filename = "#{timestamp}_#{name}.exs"
        path = Path.join(migrations_path, filename)
        create_file(path, migration_content(name))
      end
    end
  end

  defp generate_timestamp(offset) do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    ss = min(ss + offset, 59)
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: "0#{i}"
  defp pad(i), do: "#{i}"

  defp migration_content("create_dai_folders") do
    """
    defmodule MyApp.Repo.Migrations.CreateDaiFolders do
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
    """
  end

  defp migration_content("create_dai_saved_queries") do
    """
    defmodule MyApp.Repo.Migrations.CreateDaiSavedQueries do
      use Ecto.Migration

      def change do
        create table(:dai_saved_queries, primary_key: false) do
          add :id, :binary_id, primary_key: true
          add :folder_id, references(:dai_folders, type: :binary_id, on_delete: :delete_all), null: false
          add :prompt, :text, null: false
          add :title, :string
          add :position, :integer

          timestamps(type: :utc_datetime)
        end

        create index(:dai_saved_queries, [:folder_id])
      end
    end
    """
  end

  defp migration_content("create_dai_dashboard_layouts") do
    """
    defmodule MyApp.Repo.Migrations.CreateDaiDashboardLayouts do
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
    """
  end

  defp migration_content("create_dai_dashboard_preferences") do
    """
    defmodule MyApp.Repo.Migrations.CreateDaiDashboardPreferences do
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
    """
  end
end
