defmodule DocumentOcr.Documents do
  @moduledoc "Document ingestion, idempotent reuse and atomic processing transitions."
  # Ecto.Multi's MapSet representation triggers an OTP 28 opaque-type false positive.
  @dialyzer {:nowarn_function, reuse_document: 2}
  use DocumentOcr, :repository
  alias DocumentOcr.Documents.Document
  alias DocumentOcr.Documents.DocumentRepo
  alias DocumentOcr.Documents.Processor
  alias DocumentOcr.ProcessingConfig
  alias DocumentOcr.Repo
  @type result :: {:ok, map()} | {:error, term()} | {:error, term(), term(), map()}

  @spec get_document(String.t()) :: Document.t() | nil
  defdelegate get_document(id), to: DocumentRepo
  @spec get_document!(Ecto.UUID.t()) :: Document.t()
  defdelegate get_document!(id), to: DocumentRepo
  @spec lock(Ecto.UUID.t()) :: Document.t() | nil
  defdelegate lock(id), to: DocumentRepo
  @spec artifact(Document.t() | Ecto.UUID.t(), String.t()) :: map() | nil
  defdelegate artifact(document, kind), to: DocumentRepo
  @spec job_args(Document.t()) :: map()
  def job_args(document), do: %{document_id: document.id, run_id: document.run_id}

  @spec create_document_from_uploads(map(), [map()]) :: result()
  defdelegate create_document_from_uploads(attrs, uploads),
    to: DocumentOcr.Documents.Ingestion,
    as: :create

  @spec create_document(map()) :: result()
  def create_document(attrs) do
    fingerprint =
      KycCore.Idempotency.fingerprint(
        attrs
        |> Map.take([:document_type, :country, :images])
        |> Map.put(:external_id, Map.get(attrs, :requested_external_id, attrs[:external_id]))
      )

    DocumentOcr.Requests.run(
      Repo,
      :ocr,
      attrs.app_id,
      attrs[:idempotency_key],
      fingerprint,
      fn ->
        existing = DocumentRepo.existing_by_idempotency(attrs)
        reuse_document(existing, attrs)
      end,
      fn id -> reuse_document(DocumentRepo.get_document(id), attrs) end
    )
  end

  defp reuse_document(%Document{} = document, attrs) do
    fields = [:external_id, :document_type, :country]

    matches =
      Map.take(document, fields) == Map.take(attrs, fields) and
        image_identity(document.images) == image_identity(attrs.images)

    reuse_matching(matches, document)
  end

  defp reuse_document(nil, attrs) do
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

  defp reuse_matching(true, document), do: {:ok, %{document: document, job: nil}}
  defp reuse_matching(false, _document), do: {:error, :idempotency_conflict}

  defp image_identity(images),
    do:
      images
      |> Enum.map(&{Map.get(&1, :side), Map.get(&1, :source_key), Map.get(&1, :blob_id)})
      |> Enum.sort()

  @spec reprocess_document(String.t(), String.t(), String.t()) ::
          {:ok, Document.t()} | {:error, term()}
  def reprocess_document(id, version, request_id \\ Ecto.UUID.generate()) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, profile} <- ProcessingConfig.capture(version) do
      Repo.transaction(fn ->
        document = lock(id) || Repo.rollback(:document_not_found)
        # Composite foreign keys prohibit keeping results from an earlier run.
        :ok = DocumentRepo.clear_run(id)

        with {:ok, document} <- Processor.restart(document, profile, request_id),
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

  @spec cancel_document(String.t()) :: {:ok, Document.t()} | {:error, term()}
  def cancel_document(id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.transaction(fn ->
        document = lock(id) || Repo.rollback(:document_not_found)

        with :ok <- cancellable(document.status),
             {:ok, cancelled} <- Processor.cancel(document) do
          cancelled
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      :error -> {:error, :document_not_found}
    end
  end

  defp cancellable(status) when status in ["pending", "processing"], do: :ok
  defp cancellable(_), do: {:error, :not_cancellable}

  @spec save_artifact(Document.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def save_artifact(document, kind, data),
    do: with_current_run(document, &DocumentRepo.save_artifact(&1, kind, data))

  @spec save_result(Document.t(), map()) :: {:ok, map()} | {:error, term()}
  def save_result(document, data),
    do: with_current_run(document, &DocumentRepo.save_result(&1, data))

  @spec save_artifact_and_enqueue(Document.t(), String.t(), map(), module()) ::
          :ok | {:error, term()}
  def save_artifact_and_enqueue(document, kind, data, worker),
    do: save_and_enqueue(document, worker, kind, &DocumentRepo.save_artifact(&1, kind, data))

  @spec save_result_and_enqueue(Document.t(), map(), module()) :: :ok | {:error, term()}
  def save_result_and_enqueue(document, data, worker),
    do: save_and_enqueue(document, worker, :result, &DocumentRepo.save_result(&1, data))

  defp save_and_enqueue(document, worker, marker, save) do
    result =
      with_current_run(document, fn current ->
        persist_stage(current, already_saved?(current, marker), worker, save)
      end)

    enqueue_result(result)
  end

  defp enqueue_result({:ok, :ok}), do: :ok
  defp enqueue_result(error), do: error

  defp already_saved?(%{run_id: run, result: %{run_id: run}}, :result), do: true
  defp already_saved?(_, :result), do: false
  defp already_saved?(current, kind), do: not is_nil(DocumentRepo.artifact(current, kind))
  defp persist_stage(_current, true, _worker, _save), do: :ok

  defp persist_stage(%{status: status} = current, false, worker, save)
       when status in ["pending", "processing"] do
    with {:ok, _} <- save.(current),
         {:ok, _} <- current |> job_args() |> worker.new() |> Oban.insert(),
         do: :ok
  end

  defp persist_stage(_, _, _, _), do: {:error, :document_not_active}

  @spec with_current_run(Document.t(), (Document.t() -> term())) ::
          {:ok, term()} | {:error, term()}
  def with_current_run(expected, fun) do
    Repo.transaction(fn ->
      current = lock(expected.id) || Repo.rollback(:document_not_found)
      assert_run(current.run_id == expected.run_id)
      result = fun.(current)
      unwrap(result)
    end)
  end

  defp assert_run(true), do: :ok
  defp assert_run(false), do: Repo.rollback(:stale_run)
  defp unwrap(:ok), do: :ok
  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}), do: Repo.rollback(reason)
end
