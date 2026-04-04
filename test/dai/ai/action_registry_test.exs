defmodule Dai.AI.ActionRegistryTest do
  use ExUnit.Case, async: true

  alias Dai.AI.ActionRegistry

  defmodule TestAction do
    @behaviour Dai.Action

    def id, do: "test_action"
    def label, do: "Test Action"
    def description, do: "A test action for unit tests"
    def target_table, do: "users"
    def target_key, do: "id"
    def confirm_message(target), do: "Run test on #{target["name"]}?"
    def execute(_target, _params), do: {:ok, :done}
  end

  defmodule AnotherAction do
    @behaviour Dai.Action

    def id, do: "another_action"
    def label, do: "Another Action"
    def description, do: "Another test action"
    def target_table, do: "plans"
    def target_key, do: "id"
    def confirm_message(_target), do: "Run another action?"
    def execute(_target, _params), do: {:ok, :done}
  end

  setup do
    prev = Application.get_env(:dai, :actions)
    Application.put_env(:dai, :actions, [TestAction, AnotherAction])

    on_exit(fn ->
      if prev,
        do: Application.put_env(:dai, :actions, prev),
        else: Application.delete_env(:dai, :actions)
    end)
  end

  describe "all/0" do
    test "returns metadata for all configured actions" do
      actions = ActionRegistry.all()
      assert length(actions) == 2
      assert %{id: "test_action", label: "Test Action", module: TestAction} = hd(actions)
    end

    test "returns empty list when no actions configured" do
      Application.put_env(:dai, :actions, [])
      assert ActionRegistry.all() == []
    end
  end

  describe "lookup/1" do
    test "finds action by string id" do
      assert {:ok, TestAction} = ActionRegistry.lookup("test_action")
    end

    test "returns :error for unknown id" do
      assert :error = ActionRegistry.lookup("nonexistent")
    end
  end

  describe "prompt_section/0" do
    test "generates prompt text listing all actions" do
      section = ActionRegistry.prompt_section()
      assert section =~ "test_action"
      assert section =~ "Test Action"
      assert section =~ "users"
      assert section =~ "action_id"
    end

    test "returns empty string when no actions configured" do
      Application.put_env(:dai, :actions, [])
      assert ActionRegistry.prompt_section() == ""
    end
  end
end
