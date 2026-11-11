defmodule DocumentOcr.Documents.Ingestion do
  @moduledoc "Atomic document upload ownership and tenant-scoped replay bindings."
  alias AikeStorage.Transaction
  alias DocumentOcr.{Documents, ProcessingConfig, Repo}
  alias DocumentOcr.Documents.{Document, DocumentRepo}
  alias DocumentOcr.Requests
  alias KycCore.Idempotency

  @spec create(map(), [map()]) :: term()
  def create(attrs, uploads) do
    images = Enum.map(uploads, &%{side: &1.side})
    changeset = Document.changeset(%Document{}, Map.put(attrs, :images, images))

    with true <- changeset.valid?,
         {:ok, profile} <- ProcessingConfig.capture(),
         {:ok, _} <- extractor(attrs.document_type, profile) do
      store(attrs, uploads, profile, fingerprint(attrs, uploads))
    else
      false -> {:error, :invalid_request}
      error -> error
    end
  end

  defp fingerprint(attrs, uploads) do
    Idempotency.fingerprint(
      {attrs
       |> Map.take([:document_type, :country])
       |> Map.put(:external_id, Map.get(attrs, :requested_external_id, attrs[:external_id])),
       signature(uploads)}
    )
  end

  defp store(attrs, uploads, profile, fingerprint) do
    AikeStorage.Ingestion.run(DocumentOcr.BlobOwner.owner(), uploads, fn blobs ->
      Requests.run(
        Repo,
        :ocr,
        attrs.app_id,
        attrs[:idempotency_key],
        fingerprint,
        fn -> find_or_create(attrs, uploads, blobs, profile) end,
        &replay/1
      )
    end)
  end

  # A type without an extractor in the active configuration would only fail later in a worker.
  # An automatic type can turn out to be any supported type, so it needs them all.
  defp extractor("auto", profile) do
    with {:ok, _} <- extractor("cnh", profile), do: extractor("rg", profile)
  end

  defp extractor(document_type, profile) do
    case ProcessingConfig.extractor(document_type, profile.extractor_version) do
      {:ok, module} -> {:ok, module}
      {:error, _} -> {:error, :invalid_request}
    end
  end

  defp find_or_create(attrs, uploads, blobs, profile) do
    existing = DocumentRepo.existing_by_idempotency(attrs)
    resolve_legacy(existing, attrs, uploads, blobs, profile)
  end

  defp resolve_legacy(%Document{} = document, attrs, uploads, _blobs, _profile) do
    stored = document.images |> Enum.map(&{&1.side, &1.blob && &1.blob.sha256}) |> Enum.sort()

    expected =
      uploads
      |> Enum.map(&{&1.side, Base.encode16(:crypto.hash(:sha256, &1.binary), case: :lower)})
      |> Enum.sort()

    fields = [:external_id, :document_type, :country]

    legacy_match(
      stored == expected and Map.take(document, fields) == Map.take(attrs, fields),
      document
    )
  end

  defp resolve_legacy(nil, attrs, uploads, blobs, profile) do
    identity =
      {:ocr_content, attrs.app_id, attrs.document_type, attrs.country, signature(uploads),
       profile}

    Transaction.run(Repo, identity, fn ->
      found = DocumentRepo.completed_upload(attrs, uploads, profile)
      reuse_or_create(found, attrs, uploads, blobs)
    end)
  end

  defp legacy_match(true, document), do: response(document)
  defp legacy_match(false, _document), do: {:error, :idempotency_conflict}

  defp reuse_or_create(%Document{} = document, _attrs, _uploads, _blobs), do: response(document)

  defp reuse_or_create(nil, attrs, uploads, blobs) do
    images =
      Enum.zip_with(uploads, blobs, fn upload, blob ->
        %{side: upload.side, source_key: blob.key, blob_id: blob.id}
      end)

    # Request keys live in processing_requests, allowing multiple keys to bind one reused result.
    attrs
    |> Map.delete(:idempotency_key)
    |> Map.put(:images, images)
    |> Documents.create_document()
  end

  defp replay(id), do: id |> DocumentRepo.get_document() |> response()
  defp response(nil), do: {:error, :document_not_found}
  defp response(document), do: {:ok, %{document: document, job: nil, reused: reusable?(document)}}

  defp reusable?(%{status: status, run_id: run, result: %{run_id: run}}),
    do: status in ["completed", "rejected", "requires_confirmation"]

  defp reusable?(%{status: "failed"}), do: true
  defp reusable?(_), do: false

  defp signature(uploads),
    do: uploads |> Enum.map(&{&1.side, :crypto.hash(:sha256, &1.binary)}) |> Enum.sort()
end
