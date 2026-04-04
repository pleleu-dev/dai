defmodule Dai.Schema.Discovery do
  @moduledoc false

  def discover_schemas do
    contexts = Dai.Config.schema_contexts()
    extras = Dai.Config.extra_schemas()

    all_app_modules()
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and
        function_exported?(mod, :__schema__, 1) and
        (matches_context?(mod, contexts) or mod in extras)
    end)
  end

  def assoc_type(%Ecto.Association.BelongsTo{}), do: :belongs_to
  def assoc_type(%Ecto.Association.Has{cardinality: :many}), do: :has_many
  def assoc_type(%Ecto.Association.Has{cardinality: :one}), do: :has_one
  def assoc_type(%Ecto.Association.ManyToMany{}), do: :many_to_many
  def assoc_type(_), do: :unknown

  def format_type(type) when is_atom(type), do: Atom.to_string(type)
  def format_type({:parameterized, {Ecto.Embedded, _}}), do: "embedded"
  def format_type(type), do: inspect(type)

  defp all_app_modules do
    dai_modules = app_modules(:dai)
    host_modules = host_app_modules()
    loaded_modules = Enum.map(:code.all_loaded(), &elem(&1, 0))
    Enum.uniq(dai_modules ++ host_modules ++ loaded_modules)
  end

  defp host_app_modules do
    case Application.get_application(Dai.Config.repo()) do
      nil -> []
      :dai -> []
      host_app -> app_modules(host_app)
    end
  end

  defp app_modules(app) do
    case :application.get_key(app, :modules) do
      {:ok, mods} -> mods
      _ -> []
    end
  end

  defp matches_context?(_mod, []), do: true

  defp matches_context?(mod, contexts) do
    mod_string = Atom.to_string(mod)

    Enum.any?(contexts, fn ctx ->
      String.starts_with?(mod_string, Atom.to_string(ctx))
    end)
  end
end
