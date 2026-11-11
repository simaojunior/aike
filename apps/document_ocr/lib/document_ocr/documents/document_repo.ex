defmodule DocumentOcr.Documents.DocumentRepo do
  @moduledoc "Document queries, row locks and run-scoped artifact persistence."
  use DocumentOcr, :repository
  alias DocumentOcr.Documents.{Document, DocumentArtifact, DocumentResult}
  alias DocumentOcr.ProcessingConfig
  @type id :: Ecto.UUID.t()
  @spec completed_upload(map(), [map()], map()) :: Document.t() | nil
  def completed_upload(attrs, uploads, profile) do
    signature =
      uploads
      |> Enum.map(fn upload ->
        {upload.side, :crypto.hash(:sha256, upload.binary) |> Base.encode16(case: :lower)}
      end)
      |> Enum.sort()

    [{side, sha256} | _] = signature

    from(document in Document,
      join: image in assoc(document, :images),
      join: blob in assoc(image, :blob),
      left_join: result in assoc(document, :result),
      where: [
        app_id: ^attrs.app_id,
        document_type: ^attrs.document_type,
        country: ^attrs.country,
        pipeline_version: ^profile.pipeline_version,
        ocr_engine: ^profile.ocr_engine,
        ocr_engine_version: ^profile.ocr_engine_version,
        extractor_version: ^profile.extractor_version
      ],
      where:
        (document.status in ["pending", "processing"] or
           (document.status in ["completed", "rejected", "requires_confirmation"] and
              result.run_id == document.run_id)) and
          image.side == ^side and blob.sha256 == ^sha256,
      order_by: [desc: document.inserted_at],
      preload: [images: :blob, result: []]
    )
    |> Repo.all()
    |> Enum.find(fn document ->
      stored = Enum.map(document.images, &{&1.side, &1.blob && &1.blob.sha256}) |> Enum.sort()
      stored == signature
    end)
  end

  @spec get_document(String.t()) :: Document.t() | nil
  def get_document(id) do
    parsed = Ecto.UUID.cast(id)

    case parsed do
      {:ok, uuid} -> Repo.get(Document, uuid) |> preload()
      :error -> nil
    end
  end

  @spec get_document!(id()) :: Document.t()
  def get_document!(id), do: Repo.get!(Document, id) |> preload()
  defp preload(nil), do: nil
  defp preload(document), do: Repo.preload(document, images: :blob, result: [])

  @spec existing_by_idempotency(map()) :: Document.t() | nil
  def existing_by_idempotency(%{app_id: app_id, idempotency_key: key})
      when is_binary(app_id) and is_binary(key) and key != "",
      do: Repo.get_by(Document, app_id: app_id, idempotency_key: key) |> preload()

  def existing_by_idempotency(_), do: nil

  @spec artifact(Document.t() | id(), String.t()) :: map() | nil
  def artifact(%Document{} = document, kind),
    do:
      Repo.get_by(DocumentArtifact, document_id: document.id, run_id: document.run_id, kind: kind)

  def artifact(id, kind) do
    document = get_document(id)

    case document do
      nil -> nil
      document -> artifact(document, kind)
    end
  end

  @spec save_artifact(Document.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def save_artifact(current, kind, data) do
    Repo.insert(
      %DocumentArtifact{document_id: current.id, run_id: current.run_id, kind: kind, data: data},
      on_conflict: {:replace, [:data, :updated_at]},
      conflict_target: [:document_id, :kind]
    )
  end

  @spec save_result(Document.t(), map()) :: {:ok, map()} | {:error, term()}
  def save_result(document, data) do
    with {:ok, profile} <- ProcessingConfig.metadata(document) do
      Repo.insert(
        %DocumentResult{
          document_id: document.id,
          run_id: document.run_id,
          data: data,
          overall_confidence: DocumentOcr.Validation.confidence(data),
          pipeline_version: profile.pipeline_version,
          ocr_engine: profile.ocr_engine,
          ocr_engine_version: profile.ocr_engine_version,
          extractor_version: profile.extractor_version
        },
        on_conflict:
          {:replace,
           [
             :data,
             :run_id,
             :overall_confidence,
             :pipeline_version,
             :ocr_engine,
             :ocr_engine_version,
             :extractor_version,
             :updated_at
           ]},
        conflict_target: [:document_id]
      )
    end
  end

  @spec lock(id()) :: Document.t() | nil
  def lock(id),
    do: Repo.one(from(d in Document, where: d.id == ^id, lock: "FOR UPDATE")) |> preload()

  @spec clear_run(id()) :: :ok
  def clear_run(id) do
    Repo.delete_all(from(a in DocumentArtifact, where: a.document_id == ^id))
    Repo.delete_all(from(r in DocumentResult, where: r.document_id == ^id))
    :ok
  end
end
