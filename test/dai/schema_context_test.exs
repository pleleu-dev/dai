defmodule Dai.SchemaContextTest do
  use Dai.DataCase, async: true

  alias Dai.SchemaContext

  describe "get/0" do
    test "returns a non-empty schema context string" do
      context = SchemaContext.get()
      assert is_binary(context)
      assert String.contains?(context, "plans")
      assert String.contains?(context, "users")
      assert String.contains?(context, "subscriptions")
    end

    test "includes column information" do
      context = SchemaContext.get()
      assert String.contains?(context, "email")
      assert String.contains?(context, "amount_cents")
      assert String.contains?(context, "status")
    end

    test "includes association information" do
      context = SchemaContext.get()
      assert String.contains?(context, "belongs_to")
      assert String.contains?(context, "has_many")
    end
  end
end
