defmodule Mix.Tasks.GenSchemaContext do
  @moduledoc "Prints the schema context that Dai sees. Useful for debugging."
  @shortdoc "Show Dai schema context"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    context = Dai.SchemaContext.get()
    Mix.shell().info(context)
  end
end
