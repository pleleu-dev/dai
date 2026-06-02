defmodule Dai.FoldersTest do
  use Dai.DataCase, async: true

  alias Dai.Folders
  alias Dai.Folders.{Folder, SavedQuery}

  @user_a "user-a-token"
  @user_b "user-b-token"

  describe "folders" do
    test "list_folders/1 returns only the caller's folders, ordered by position" do
      {:ok, f2} = Folders.create_folder(@user_a, %{name: "Second", position: 2})
      {:ok, f1} = Folders.create_folder(@user_a, %{name: "First", position: 1})
      {:ok, _other} = Folders.create_folder(@user_b, %{name: "Theirs", position: 1})

      assert [%Folder{id: id1}, %Folder{id: id2}] = Folders.list_folders(@user_a)
      assert id1 == f1.id
      assert id2 == f2.id
    end

    test "create_folder/2 with valid attrs creates a folder owned by the caller" do
      assert {:ok, %Folder{name: "My Folder", user_token: @user_a}} =
               Folders.create_folder(@user_a, %{name: "My Folder"})
    end

    test "create_folder/2 without name returns error" do
      assert {:error, changeset} = Folders.create_folder(@user_a, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "get_folder!/2 returns the caller's folder" do
      {:ok, folder} = Folders.create_folder(@user_a, %{name: "Test"})
      assert Folders.get_folder!(@user_a, folder.id).id == folder.id
    end

    test "update_folder/2 updates the folder name" do
      {:ok, folder} = Folders.create_folder(@user_a, %{name: "Old"})
      assert {:ok, %Folder{name: "New"}} = Folders.update_folder(folder, %{name: "New"})
    end

    test "delete_folder/1 removes the folder" do
      {:ok, folder} = Folders.create_folder(@user_a, %{name: "Doomed"})
      assert {:ok, _} = Folders.delete_folder(folder)
      assert_raise Ecto.NoResultsError, fn -> Folders.get_folder!(@user_a, folder.id) end
    end

    test "delete_folder/1 cascades to saved queries" do
      {:ok, folder} = Folders.create_folder(@user_a, %{name: "Cascade"})

      {:ok, _query} =
        Folders.create_saved_query(@user_a, %{folder_id: folder.id, prompt: "test?"})

      assert {:ok, _} = Folders.delete_folder(folder)
      assert Folders.list_saved_queries(@user_a, folder.id) == []
    end
  end

  describe "folder ownership isolation (T3.5, IDOR)" do
    setup do
      {:ok, folder} = Folders.create_folder(@user_b, %{name: "B's Folder"})
      %{folder: folder}
    end

    test "list_folders/1 never returns another user's folders", %{folder: folder} do
      ids = Enum.map(Folders.list_folders(@user_a), & &1.id)
      refute folder.id in ids
    end

    test "get_folder!/2 raises when fetching another user's folder", %{folder: folder} do
      assert_raise Ecto.NoResultsError, fn -> Folders.get_folder!(@user_a, folder.id) end
    end

    test "rename_folder/3 cannot rename another user's folder", %{folder: folder} do
      assert {:error, :not_found} = Folders.rename_folder(@user_a, folder.id, "Hijacked")
      assert Folders.get_folder!(@user_b, folder.id).name == "B's Folder"
    end

    test "delete_folder_by_id/2 cannot delete another user's folder", %{folder: folder} do
      assert {:error, :not_found} = Folders.delete_folder_by_id(@user_a, folder.id)
      assert Folders.get_folder!(@user_b, folder.id).id == folder.id
    end

    test "rename_folder/3 succeeds for the owner", %{folder: folder} do
      assert {:ok, %Folder{name: "Renamed"}} =
               Folders.rename_folder(@user_b, folder.id, "Renamed")
    end
  end

  describe "saved_queries" do
    setup do
      {:ok, folder} = Folders.create_folder(@user_a, %{name: "Test Folder"})
      %{folder: folder}
    end

    test "list_saved_queries/2 returns only the caller's queries, ordered", %{folder: folder} do
      {:ok, q2} =
        Folders.create_saved_query(@user_a, %{folder_id: folder.id, prompt: "q2", position: 2})

      {:ok, q1} =
        Folders.create_saved_query(@user_a, %{folder_id: folder.id, prompt: "q1", position: 1})

      assert [%SavedQuery{id: id1}, %SavedQuery{id: id2}] =
               Folders.list_saved_queries(@user_a, folder.id)

      assert id1 == q1.id
      assert id2 == q2.id
    end

    test "create_saved_query/2 with valid attrs", %{folder: folder} do
      assert {:ok, %SavedQuery{prompt: "revenue?", title: "revenue?", user_token: @user_a}} =
               Folders.create_saved_query(@user_a, %{folder_id: folder.id, prompt: "revenue?"})
    end

    test "create_saved_query/2 sets default title from prompt", %{folder: folder} do
      long_prompt = String.duplicate("a", 80)

      assert {:ok, %SavedQuery{title: title}} =
               Folders.create_saved_query(@user_a, %{folder_id: folder.id, prompt: long_prompt})

      assert String.length(title) <= 60
      assert String.ends_with?(title, "...")
    end

    test "create_saved_query/2 uses provided title over prompt", %{folder: folder} do
      assert {:ok, %SavedQuery{title: "Custom"}} =
               Folders.create_saved_query(@user_a, %{
                 folder_id: folder.id,
                 prompt: "some long question",
                 title: "Custom"
               })
    end

    test "create_saved_query/2 without prompt returns error", %{folder: folder} do
      assert {:error, changeset} = Folders.create_saved_query(@user_a, %{folder_id: folder.id})
      assert %{prompt: ["can't be blank"]} = errors_on(changeset)
    end

    test "update_saved_query/2 updates title", %{folder: folder} do
      {:ok, query} = Folders.create_saved_query(@user_a, %{folder_id: folder.id, prompt: "test?"})

      assert {:ok, %SavedQuery{title: "Renamed"}} =
               Folders.update_saved_query(query, %{title: "Renamed"})
    end

    test "delete_saved_query/1 removes the query", %{folder: folder} do
      {:ok, query} = Folders.create_saved_query(@user_a, %{folder_id: folder.id, prompt: "test?"})
      assert {:ok, _} = Folders.delete_saved_query(query)
      assert Folders.list_saved_queries(@user_a, folder.id) == []
    end

    test "save_query_to_new_folder/4 creates a folder and query owned by the caller" do
      assert {:ok, %{folder: folder, query: query}} =
               Folders.save_query_to_new_folder(@user_a, "show me MRR", "MRR", 0)

      assert folder.user_token == @user_a
      assert query.user_token == @user_a
      assert query.folder_id == folder.id
    end
  end

  describe "saved query ownership isolation (T3.5, IDOR)" do
    setup do
      {:ok, folder} = Folders.create_folder(@user_b, %{name: "B's Folder"})
      {:ok, query} = Folders.create_saved_query(@user_b, %{folder_id: folder.id, prompt: "B's q"})
      %{folder: folder, query: query}
    end

    test "list_saved_queries/2 never returns another user's queries", %{
      folder: folder,
      query: query
    } do
      ids = Enum.map(Folders.list_saved_queries(@user_a, folder.id), & &1.id)
      refute query.id in ids
    end

    test "create_saved_query/2 cannot target another user's folder", %{folder: folder} do
      assert {:error, :not_found} =
               Folders.create_saved_query(@user_a, %{folder_id: folder.id, prompt: "sneaky?"})

      assert Folders.list_saved_queries(@user_b, folder.id) |> Enum.map(& &1.prompt) == ["B's q"]
    end

    test "rename_saved_query/3 cannot rename another user's query", %{query: query} do
      assert {:error, :not_found} = Folders.rename_saved_query(@user_a, query.id, "Hijacked")
      assert Folders.get_saved_query!(@user_b, query.id).title == "B's q"
    end

    test "delete_saved_query_by_id/2 cannot delete another user's query", %{query: query} do
      assert {:error, :not_found} = Folders.delete_saved_query_by_id(@user_a, query.id)
      assert Folders.get_saved_query!(@user_b, query.id).id == query.id
    end

    test "owner can rename and delete their own query", %{query: query} do
      assert {:ok, %SavedQuery{title: "Mine"}} =
               Folders.rename_saved_query(@user_b, query.id, "Mine")

      assert {:ok, _} = Folders.delete_saved_query_by_id(@user_b, query.id)
    end
  end
end
