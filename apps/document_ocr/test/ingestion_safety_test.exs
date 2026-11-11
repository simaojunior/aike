defmodule DocumentOcr.IngestionSafetyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias DocumentOcr.{Documents, Repo}
  alias AikeStorage.{Blob, Blobs, Ingestion}
  alias AikeStorage.Adapter.Fake

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Fake.reset()
    :ok
  end

  defp attrs(key),
    do: %{
      app_id: "safety",
      external_id: "document",
      document_type: "cnh",
      country: "BR",
      request_id: "request",
      idempotency_key: key
    }

  defp upload(bytes),
    do: %{side: "front", binary: bytes, filename: "front.jpg", mime_type: "image/jpeg"}

  test "same key with changed bytes conflicts without storing the second file" do
    assert {:ok, first} =
             Documents.create_document_from_uploads(attrs("same-key"), [upload("first")])

    assert {:error, :idempotency_conflict} =
             Documents.create_document_from_uploads(attrs("same-key"), [upload("different")])

    assert {:ok, repeated} =
             Documents.create_document_from_uploads(attrs("same-key"), [upload("first")])

    assert repeated.document.id == first.document.id
    assert Repo.aggregate(Blob, :count) == 1
    assert Repo.aggregate(Oban.Job, :count) == 1
  end

  test "failed parent creation rolls back blobs and compensates files, preserving shared bytes" do
    {:ok, existing} =
      Blobs.put("shared", "front.jpg", "image/jpeg", DocumentOcr.BlobOwner.owner())

    uploads = [upload("shared"), upload("new")]

    assert {:error, :forced_failure} =
             Ingestion.run(DocumentOcr.BlobOwner.owner(), uploads, fn _ ->
               {:error, :forced_failure}
             end)

    assert {:ok, "shared"} = Fake.get(existing.key)
    assert Repo.aggregate(Blob, :count) == 1
    {_, new_key, _} = AikeStorage.Key.for("new", "front.jpg")
    assert {:error, :not_found} = Fake.get(new_key)
  end

  test "referenced blobs cannot be deleted or purged, and bytes remain readable" do
    {:ok, creation} = Documents.create_document_from_uploads(attrs(nil), [upload("referenced")])
    document = Documents.get_document!(creation.document.id)
    blob = hd(document.images).blob
    assert {:error, :blob_in_use} = Blobs.delete(blob, DocumentOcr.BlobOwner.owner())
    assert {:ok, "referenced"} = Blobs.get(blob)

    assert {:ok, 0} =
             Blobs.purge_expired(
               DocumentOcr.BlobOwner.owner(),
               DateTime.add(DateTime.utc_now(), 3600),
               0
             )

    assert Repo.get!(Blob, blob.id)
    assert {:ok, "referenced"} = Blobs.get(blob)
  end

  test "failure after enqueue rolls back the parent, job and request binding together" do
    assert {:error, :after_enqueue} =
             Ingestion.run(DocumentOcr.BlobOwner.owner(), [upload("rollback-all")], fn [blob] ->
               assert {:ok, _} =
                        Documents.create_document(
                          Map.put(attrs("rollback-key"), :images, [
                            %{side: "front", blob_id: blob.id, source_key: blob.key}
                          ])
                        )

               {:error, :after_enqueue}
             end)

    assert Repo.aggregate(DocumentOcr.Documents.Document, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0
    assert Repo.aggregate(DocumentOcr.Requests.Request, :count) == 0
    assert Repo.aggregate(Blob, :count) == 0
    {_, key, _} = AikeStorage.Key.for("rollback-all", "front.jpg")
    assert {:error, :not_found} = Fake.get(key)
  end

  test "a second key bound to reused content remains bound to that request" do
    {:ok, first} =
      Documents.create_document_from_uploads(attrs("first-key"), [upload("shared-key-content")])

    {:ok, alias_result} =
      Documents.create_document_from_uploads(attrs("second-key"), [upload("shared-key-content")])

    assert first.document.id == alias_result.document.id

    assert {:error, :idempotency_conflict} =
             Documents.create_document_from_uploads(attrs("second-key"), [upload("changed-alias")])

    assert Repo.aggregate(DocumentOcr.Requests.Request, :count) == 2
    Repo.delete!(first.document)
    assert Repo.aggregate(DocumentOcr.Requests.Request, :count) == 0
  end

  test "legacy document keys are checked before binding new requests" do
    {:ok, blob} = Blobs.put("legacy", "front.jpg", "image/jpeg", DocumentOcr.BlobOwner.owner())

    {:ok, %{document: original}} =
      Documents.create_document(
        Map.put(attrs("legacy-key"), :images, [
          %{side: "front", source_key: blob.key, blob_id: blob.id}
        ])
      )

    Repo.delete_all(DocumentOcr.Requests.Request)

    assert {:ok, replay} =
             Documents.create_document_from_uploads(attrs("legacy-key"), [upload("legacy")])

    assert replay.document.id == original.id
    Repo.delete_all(DocumentOcr.Requests.Request)

    assert {:error, :idempotency_conflict} =
             Documents.create_document_from_uploads(attrs("legacy-key"), [upload("changed")])
  end

  test "same in-flight content reuses one document and job without a request key" do
    {:ok, first} = Documents.create_document_from_uploads(attrs(nil), [upload("pending")])
    {:ok, second} = Documents.create_document_from_uploads(attrs(nil), [upload("pending")])
    assert first.document.id == second.document.id

    assert Repo.aggregate(
             from(j in Oban.Job, where: j.worker == "DocumentOcr.Workers.PreprocessDocument"),
             :count
           ) == 1
  end
end
