defmodule DocumentOcr.Documents do
  @dialyzer {:nowarn_function, create_new_document: 1}

  import Ecto.Query

  alias DocumentOcr.Repo
  alias DocumentOcr.ProcessingConfig
  alias DocumentOcr.Documents.{Document, DocumentArtifact, DocumentResult}

  @type id :: Ecto.UUID.t()
  @type attrs :: map()

  def create_document_from_uploads(attrs, uploads) when is_list(uploads) do
    case existing_by_idempotency(attrs) do
      %Document{} = document ->
        {:ok, %{document: document, job: nil}}

      nil ->
        with {:ok, images} <- store_uploads(uploads) do
          create_document(Map.put(attrs, :images, images))
        end
    end
  end

  @spec get_document(String.t()) :: Document.t() | nil
  def get_document(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Document, uuid) |> preload()
      :error -> nil
    end
  end

  @spec get_document!(id()) :: Document.t()
  def get_document!(id), do: Repo.get!(Document, id) |> preload()
  defp preload(nil), do: nil
  defp preload(document), do: Repo.preload(document, images: :blob, result: [])

  @spec create_document(attrs()) :: {:ok, map()} | {:error, term()}
  def create_document(attrs) do
    case existing_by_idempotency(attrs) do
      %Document{} = document -> {:ok, %{document: document, job: nil}}
      nil -> create_new_document(attrs)
    end
  end

  defp create_new_document(attrs) do
    with {:ok, profile} <- ProcessingConfig.capture() do
      changeset =
        Document.changeset(%Document{}, attrs)
        |> Ecto.Changeset.change(Map.put(profile, :run_id, Ecto.UUID.generate()))

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:document, changeset)
      |> Oban.insert(:job, fn %{document: doc} ->
        DocumentOcr.Workers.PreprocessDocument.new(job_args(doc))
      end)
      |> Repo.transaction()
    end
  end

  defp existing_by_idempotency(%{app_id: app_id, idempotency_key: key})
       when is_binary(app_id) and is_binary(key) and key != "",
       do: Repo.get_by(Document, app_id: app_id, idempotency_key: key) |> preload()

  defp existing_by_idempotency(_), do: nil

  @spec job_args(Document.t()) :: map()
  def job_args(%Document{} = document), do: %{document_id: document.id, run_id: document.run_id}

  def reprocess_document(id, version, request_id \\ Ecto.UUID.generate()) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, profile} <- ProcessingConfig.capture(version) do
      Repo.transaction(fn ->
        document = lock(id) || Repo.rollback(:document_not_found)
        # Delete first: composite FKs prohibit retaining a result from a different run.
        Repo.delete_all(from(a in DocumentArtifact, where: a.document_id == ^id))
        Repo.delete_all(from(r in DocumentResult, where: r.document_id == ^id))

        with {:ok, document} <-
               DocumentOcr.Documents.Processor.restart(document, profile, request_id),
             {:ok, _job} <-
               document
               |> job_args()
               |> DocumentOcr.Workers.PreprocessDocument.new()
               |> Oban.insert() do
          document
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      :error -> {:error, :document_not_found}
      error -> error
    end
  end

  def cancel_document(id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.transaction(fn ->
        document = lock(id) || Repo.rollback(:document_not_found)

        if document.status in ["pending", "processing"] do
          case DocumentOcr.Documents.Processor.cancel(document) do
            {:ok, cancelled} -> cancelled
            {:error, reason} -> Repo.rollback(reason)
          end
        else
          Repo.rollback(:not_cancellable)
        end
      end)
    else
      :error -> {:error, :document_not_found}
    end
  end

  def artifact(%Document{} = document, kind),
    do:
      Repo.get_by(DocumentArtifact, document_id: document.id, run_id: document.run_id, kind: kind)

  def artifact(id, kind) do
    case get_document(id) do
      nil -> nil
      document -> artifact(document, kind)
    end
  end

  def save_artifact(document, kind, data) do
    with_current_run(document, fn current ->
      Repo.insert(
        %DocumentArtifact{
          document_id: current.id,
          run_id: current.run_id,
          kind: kind,
          data: data
        },
        on_conflict: {:replace, [:data, :updated_at]},
        conflict_target: [:document_id, :kind]
      )
    end)
  end

  def save_result(document, data) do
    with_current_run(document, fn document ->
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
    end)
  end

  def save_artifact_and_enqueue(document, kind, data, worker) do
    case with_current_run(document, fn current ->
           with {:ok, _artifact} <- save_artifact_locked(current, kind, data),
                {:ok, _job} <- current |> job_args() |> worker.new() |> Oban.insert() do
             :ok
           end
         end) do
      {:ok, :ok} -> :ok
      other -> other
    end
  end

  def save_result_and_enqueue(document, data, worker) do
    case with_current_run(document, fn current ->
           with {:ok, _result} <- save_result_locked(current, data),
                {:ok, _job} <- current |> job_args() |> worker.new() |> Oban.insert() do
             :ok
           end
         end) do
      {:ok, :ok} -> :ok
      other -> other
    end
  end

  @doc false
  def with_current_run(%Document{} = expected, fun) do
    Repo.transaction(fn ->
      current = lock(expected.id) || Repo.rollback(:document_not_found)
      if current.run_id != expected.run_id, do: Repo.rollback(:stale_run)

      case fun.(current) do
        :ok -> :ok
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp save_artifact_locked(current, kind, data) do
    Repo.insert(
      %DocumentArtifact{document_id: current.id, run_id: current.run_id, kind: kind, data: data},
      on_conflict: {:replace, [:data, :updated_at]},
      conflict_target: [:document_id, :kind]
    )
  end

  defp save_result_locked(document, data) do
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

  def lock(id),
    do: Repo.one(from(d in Document, where: d.id == ^id, lock: "FOR UPDATE")) |> preload()

  defp store_uploads(uploads) do
    Enum.reduce_while(uploads, {:ok, []}, fn upload, {:ok, acc} ->
      case AikeStorage.Blobs.put(upload.binary, upload.filename, upload.mime_type) do
        {:ok, blob} ->
          {:cont, {:ok, [%{side: upload.side, source_key: blob.key, blob_id: blob.id} | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, images} -> {:ok, Enum.reverse(images)}
      error -> error
    end
  end
end
