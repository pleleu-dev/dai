defmodule Dai.FoldersTest do
  use Dai.DataCase, async: true

  alias Dai.Folders
  alias Dai.Folders.{Folder, SavedQuery}

  describe "folders" do
    test "list_folders/0 returns all folders ordered by position" do
      {:ok, f2} = Folders.create_folder(%{name: "Second", position: 2})
      {:ok, f1} = Folders.create_folder(%{name: "First", position: 1})

      assert [%Folder{id: id1}, %Folder{id: id2}] = Folders.list_folders()
      assert id1 == f1.id
      assert id2 == f2.id
    end

    test "create_folder/1 with valid attrs creates a folder" do
      assert {:ok, %Folder{name: "My Folder"}} = Folders.create_folder(%{name: "My Folder"})
    end

    test "create_folder/1 without name returns error" do
      assert {:error, changeset} = Folders.create_folder(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "get_folder!/1 returns the folder" do
      {:ok, folder} = Folders.create_folder(%{name: "Test"})
      assert Folders.get_folder!(folder.id).id == folder.id
    end

    test "update_folder/2 updates the folder name" do
      {:ok, folder} = Folders.create_folder(%{name: "Old"})
      assert {:ok, %Folder{name: "New"}} = Folders.update_folder(folder, %{name: "New"})
    end

    test "delete_folder/1 removes the folder" do
      {:ok, folder} = Folders.create_folder(%{name: "Doomed"})
      assert {:ok, _} = Folders.delete_folder(folder)
      assert_raise Ecto.NoResultsError, fn -> Folders.get_folder!(folder.id) end
    end

    test "delete_folder/1 cascades to saved queries" do
      {:ok, folder} = Folders.create_folder(%{name: "Cascade"})
      {:ok, _query} = Folders.create_saved_query(%{folder_id: folder.id, prompt: "test?"})

      assert {:ok, _} = Folders.delete_folder(folder)
      assert Folders.list_saved_queries(folder.id) == []
    end
  end

  describe "saved_queries" do
    setup do
      {:ok, folder} = Folders.create_folder(%{name: "Test Folder"})
      %{folder: folder}
    end

    test "list_saved_queries/1 returns queries for folder ordered by position", %{folder: folder} do
      {:ok, q2} = Folders.create_saved_query(%{folder_id: folder.id, prompt: "q2", position: 2})
      {:ok, q1} = Folders.create_saved_query(%{folder_id: folder.id, prompt: "q1", position: 1})

      assert [%SavedQuery{id: id1}, %SavedQuery{id: id2}] = Folders.list_saved_queries(folder.id)
      assert id1 == q1.id
      assert id2 == q2.id
    end

    test "create_saved_query/1 with valid attrs", %{folder: folder} do
      assert {:ok, %SavedQuery{prompt: "revenue?", title: "revenue?"}} =
               Folders.create_saved_query(%{folder_id: folder.id, prompt: "revenue?"})
    end

    test "create_saved_query/1 sets default title from prompt", %{folder: folder} do
      long_prompt = String.duplicate("a", 80)

      assert {:ok, %SavedQuery{title: title}} =
               Folders.create_saved_query(%{folder_id: folder.id, prompt: long_prompt})

      assert String.length(title) <= 60
      assert String.ends_with?(title, "...")
    end

    test "create_saved_query/1 uses provided title over prompt", %{folder: folder} do
      assert {:ok, %SavedQuery{title: "Custom"}} =
               Folders.create_saved_query(%{
                 folder_id: folder.id,
                 prompt: "some long question",
                 title: "Custom"
               })
    end

    test "create_saved_query/1 without prompt returns error", %{folder: folder} do
      assert {:error, changeset} = Folders.create_saved_query(%{folder_id: folder.id})
      assert %{prompt: ["can't be blank"]} = errors_on(changeset)
    end

    test "update_saved_query/2 updates title", %{folder: folder} do
      {:ok, query} = Folders.create_saved_query(%{folder_id: folder.id, prompt: "test?"})
      assert {:ok, %SavedQuery{title: "Renamed"}} = Folders.update_saved_query(query, %{title: "Renamed"})
    end

    test "delete_saved_query/1 removes the query", %{folder: folder} do
      {:ok, query} = Folders.create_saved_query(%{folder_id: folder.id, prompt: "test?"})
      assert {:ok, _} = Folders.delete_saved_query(query)
      assert Folders.list_saved_queries(folder.id) == []
    end
  end
end
