defmodule DocumentOcr.FailingDeleteStorage do
  @behaviour AikeStorage.Adapter
  defdelegate put(bytes, opts), to: AikeStorage.Adapter.Local
  defdelegate get(key), to: AikeStorage.Adapter.Local
  def delete(_key), do: {:error, :storage_unavailable}
end

defmodule DocumentOcr.StorageRecoveryTest do
  use ExUnit.Case, async: false
  alias AikeStorage.Adapter.Local
  alias AikeStorage.{Blobs, Reconciliation}
  alias DocumentOcr.{Documents, Repo}
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    adapter = Application.fetch_env!(:aike_storage, :adapter)
    root = Application.fetch_env!(:aike_storage, :local_root)
    directory = Path.join(System.tmp_dir!(), "aike-recovery-#{Ecto.UUID.generate()}")
    Application.put_env(:aike_storage, :adapter, Local)
    Application.put_env(:aike_storage, :local_root, directory)

    on_exit(fn ->
      Application.put_env(:aike_storage, :adapter, adapter)
      Application.put_env(:aike_storage, :local_root, root)
      File.rm_rf!(directory)
    end)

    %{root: directory}
  end

  test "reconciliation removes abandoned bytes and temp files but preserves referenced and recent files",
       %{root: root} do
    bytes = "orphaned-after-process-crash"
    hash = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    {:ok, orphan} = Local.put(bytes, sha256: hash, extension: "jpg")

    {:ok, live} =
      Documents.create_document_from_uploads(
        %{
          app_id: "gc",
          external_id: "live",
          document_type: "cnh",
          country: "BR",
          request_id: "gc"
        },
        [%{side: "front", binary: "live", filename: "live.jpg", mime_type: "image/jpeg"}]
      )

    blob = Documents.get_document!(live.document.id).images |> hd() |> Map.fetch!(:blob)
    temp = Path.join(root, orphan <> ".ABC123.tmp")
    File.write!(temp, "incomplete")
    future = DateTime.add(DateTime.utc_now(), 7200)
    assert {:ok, _} = Reconciliation.run(DocumentOcr.BlobOwner.owner(), DateTime.utc_now(), 3600)
    assert {:ok, ^bytes} = Local.get(orphan)
    assert {:ok, _} = Reconciliation.run(DocumentOcr.BlobOwner.owner(), future, 3600)
    assert {:error, :not_found} = Local.get(orphan)
    refute File.exists?(temp)
    assert {:ok, "live"} = Blobs.get(blob)
    assert {:ok, _} = Reconciliation.run(DocumentOcr.BlobOwner.owner(), future, 3600)
  end

  test "failed storage deletion retains metadata until a successful retry" do
    {:ok, blob} =
      Blobs.put("delete-retry", "retry.jpg", "image/jpeg", DocumentOcr.BlobOwner.owner())

    Application.put_env(:aike_storage, :adapter, DocumentOcr.FailingDeleteStorage)
    assert {:error, :storage_unavailable} = Blobs.delete(blob, DocumentOcr.BlobOwner.owner())
    assert Repo.get(AikeStorage.Blob, blob.id)
    assert {:ok, "delete-retry"} = Blobs.get(blob)
    Application.put_env(:aike_storage, :adapter, Local)
    assert :ok = Blobs.delete(blob, DocumentOcr.BlobOwner.owner())
    assert is_nil(Repo.get(AikeStorage.Blob, blob.id))
    assert {:error, :not_found} = Blobs.get(blob)
  end

  test "failed compensation is retried by the filesystem inventory" do
    Application.put_env(:aike_storage, :adapter, DocumentOcr.FailingDeleteStorage)
    upload = %{binary: "compensate-retry", filename: "retry.jpg", mime_type: "image/jpeg"}

    assert {:error, :forced_failure} =
             AikeStorage.Ingestion.run(DocumentOcr.BlobOwner.owner(), [upload], fn _ ->
               {:error, :forced_failure}
             end)

    {_, key, _} = AikeStorage.Key.for(upload.binary, upload.filename)
    assert {:ok, "compensate-retry"} = Local.get(key)
    Application.put_env(:aike_storage, :adapter, Local)

    assert {:ok, _} =
             Reconciliation.run(
               DocumentOcr.BlobOwner.owner(),
               DateTime.add(DateTime.utc_now(), 7200),
               3600
             )

    assert {:error, :not_found} = Local.get(key)
  end

  test "unowned metadata and its object are collected, while DB rollback alone leaves recoverable bytes" do
    {:ok, blob} = Blobs.put("unowned", "unowned.jpg", "image/jpeg", DocumentOcr.BlobOwner.owner())

    assert {:ok, 1} =
             Blobs.purge_expired(
               DocumentOcr.BlobOwner.owner(),
               DateTime.add(DateTime.utc_now(), 7200),
               3600
             )

    assert is_nil(Repo.get(AikeStorage.Blob, blob.id))
    assert {:error, :not_found} = Blobs.get(blob)
  end
end
