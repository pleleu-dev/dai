defmodule Dai.DashboardLayout do
  @moduledoc "Schema and context for persisting dashboard card grid positions."

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "dai_dashboard_layouts" do
    field :user_token, :string
    field :layout_key, :string
    field :x, :integer, default: 0
    field :y, :integer, default: 0
    field :w, :integer
    field :h, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(layout, attrs) do
    layout
    |> cast(attrs, [:user_token, :layout_key, :x, :y, :w, :h])
    |> validate_required([:user_token, :layout_key, :w, :h])
  end

  defp repo, do: Dai.Config.repo()

  @doc "Generate a layout_key by normalizing and hashing the prompt."
  def layout_key(prompt) do
    prompt
    |> String.trim()
    |> String.downcase()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  @doc "Get all saved layouts for a user, returned as a map of layout_key => %{x, y, w, h}."
  def get_layouts(user_token) do
    __MODULE__
    |> where(user_token: ^user_token)
    |> repo().all()
    |> Map.new(fn l -> {l.layout_key, %{x: l.x, y: l.y, w: l.w, h: l.h}} end)
  end

  @doc "Upsert a card's grid position."
  def save_layout(user_token, layout_key, attrs) do
    case repo().get_by(__MODULE__, user_token: user_token, layout_key: layout_key) do
      nil ->
        %__MODULE__{}
        |> changeset(Map.merge(attrs, %{user_token: user_token, layout_key: layout_key}))
        |> repo().insert()

      existing ->
        existing
        |> changeset(attrs)
        |> repo().update()
    end
  end

  @doc "Batch upsert multiple card positions atomically."
  def save_layouts(user_token, cards) when is_list(cards) do
    repo().transaction(fn ->
      Enum.each(cards, fn %{"layout_key" => key} = card ->
        case save_layout(user_token, key, %{
               x: card["x"],
               y: card["y"],
               w: card["w"],
               h: card["h"]
             }) do
          {:ok, _} -> :ok
          {:error, changeset} -> repo().rollback(changeset)
        end
      end)
    end)
  end
end
