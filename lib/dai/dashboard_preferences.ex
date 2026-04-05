defmodule Dai.DashboardPreferences do
  @moduledoc "Schema and context for persisting dashboard panel sizes."

  use Ecto.Schema
  import Ecto.Changeset

  @default_panel_sizes %{"main_split" => 75, "right_split" => 50}

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "dai_dashboard_preferences" do
    field :user_token, :string
    field :panel_sizes, :map, default: @default_panel_sizes

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(prefs, attrs) do
    prefs
    |> cast(attrs, [:user_token, :panel_sizes])
    |> validate_required([:user_token])
  end

  defp repo, do: Dai.Config.repo()

  @doc "Get preferences for a user, or return defaults."
  def get_preferences(user_token) do
    case repo().get_by(__MODULE__, user_token: user_token) do
      nil -> %{panel_sizes: @default_panel_sizes}
      prefs -> %{panel_sizes: prefs.panel_sizes}
    end
  end

  @doc "Upsert panel sizes for a user."
  def save_panel_sizes(user_token, panel_sizes) do
    case repo().get_by(__MODULE__, user_token: user_token) do
      nil ->
        %__MODULE__{}
        |> changeset(%{user_token: user_token, panel_sizes: panel_sizes})
        |> repo().insert()

      existing ->
        existing
        |> changeset(%{panel_sizes: panel_sizes})
        |> repo().update()
    end
  end
end
