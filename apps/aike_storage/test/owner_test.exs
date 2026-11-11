defmodule AikeStorage.OwnerTest do
  use ExUnit.Case, async: false
  alias AikeStorage.Adapter.Local
  alias AikeStorage.{LocalInventory, Owner}

  defp konoha(fields \\ []) do
    Owner.new(
      Keyword.merge(
        [
          repo: Konoha.Repo,
          folder: "kyc_documents",
          blob_references: [{"document_images", "blob_id"}],
          key_references: [{"document_images", "source_key"}]
        ],
        fields
      )
    )
  end

  test "refuses folder, table and column names that are not plain identifiers" do
    for fields <- [
          [folder: "../facematch"],
          [blob_references: [{"document_images; DROP TABLE blobs", "blob_id"}]],
          [key_references: [{"document_images", "source_key OR true"}]]
        ] do
      assert_raise ArgumentError, ~r/invalid storage owner identifier/, fn -> konoha(fields) end
    end
  end

  test "builds reference queries with one parameter per declared column" do
    owner = konoha()

    assert Owner.referenced_query(owner, "blob-id", "kyc_documents/a.jpg") ==
             {"SELECT EXISTS(SELECT 1 FROM document_images WHERE blob_id = $1) OR " <>
                "EXISTS(SELECT 1 FROM document_images WHERE source_key = $2)",
              ["blob-id", "kyc_documents/a.jpg"]}

    assert Owner.key_referenced_query(owner, "k") ==
             {"SELECT EXISTS(SELECT 1 FROM document_images WHERE source_key = $1)", ["k"]}

    bare = konoha(blob_references: [], key_references: [])
    assert Owner.referenced_query(bare, "blob-id", "k") == {"SELECT false", []}
    assert Owner.referenced_condition(bare) == "false"
    assert Owner.constraints(owner) == ["document_images_blob_id_fkey"]
  end

  test "each owner's inventory sees only its own folder" do
    previous = Application.fetch_env!(:aike_storage, :local_root)
    root = Path.join(System.tmp_dir!(), "aike-owner-#{System.unique_integer([:positive])}")
    Application.put_env(:aike_storage, :local_root, root)

    on_exit(fn ->
      Application.put_env(:aike_storage, :local_root, previous)
      File.rm_rf!(root)
    end)

    for {folder, bytes} <- [{"kyc_documents", "naruto"}, {"facematch", "sasuke"}] do
      hash = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      {:ok, _} = Local.put(bytes, folder: folder, sha256: hash, extension: "jpg")
    end

    assert {:ok, [%{key: "kyc_documents/" <> _}]} = LocalInventory.list("kyc_documents")
    assert {:ok, [%{key: "facematch/" <> _ = key}]} = LocalInventory.list("facematch")
    assert {:error, :invalid_key} = LocalInventory.delete_temporary(key, "kyc_documents")
  end
end
