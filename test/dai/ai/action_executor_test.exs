defmodule Dai.AI.ActionExecutorTest do
  use ExUnit.Case, async: true

  alias Dai.AI.ActionExecutor

  defmodule SuccessAction do
    @behaviour Dai.Action

    def id, do: "success"
    def label, do: "Success"
    def description, do: "Always succeeds"
    def target_table, do: "users"
    def target_key, do: "id"
    def confirm_message(target), do: "Act on #{target["name"]}?"

    def execute(target, _params) do
      {:ok, %{id: target["id"]}}
    end
  end

  defmodule FailAction do
    @behaviour Dai.Action

    def id, do: "fail"
    def label, do: "Fail"
    def description, do: "Always fails"
    def target_table, do: "users"
    def target_key, do: "id"
    def confirm_message(_target), do: "Act?"

    def execute(_target, _params) do
      {:error, "something went wrong"}
    end
  end

  describe "execute_all/3" do
    test "executes action on each target and returns all successes" do
      targets = [%{"id" => 1, "name" => "A"}, %{"id" => 2, "name" => "B"}]

      assert {:ok, results} = ActionExecutor.execute_all(SuccessAction, targets, %{})
      assert length(results) == 2
    end

    test "returns partial failure with details" do
      targets = [%{"id" => 1, "name" => "A"}]

      assert {:error, "something went wrong"} =
               ActionExecutor.execute_all(FailAction, targets, %{})
    end

    test "returns partial result when some targets fail" do
      defmodule MixedAction do
        @behaviour Dai.Action

        def id, do: "mixed"
        def label, do: "Mixed"
        def description, do: "Fails on id 2"
        def target_table, do: "users"
        def target_key, do: "id"
        def confirm_message(_target), do: "Act?"

        def execute(%{"id" => 2}, _params), do: {:error, "failed on 2"}
        def execute(target, _params), do: {:ok, %{id: target["id"]}}
      end

      targets = [%{"id" => 1, "name" => "A"}, %{"id" => 2, "name" => "B"}]
      assert {:partial, [%{id: 1}], [{%{"id" => 2, "name" => "B"}, "failed on 2"}]} =
               ActionExecutor.execute_all(MixedAction, targets, %{})
    end
  end
end
