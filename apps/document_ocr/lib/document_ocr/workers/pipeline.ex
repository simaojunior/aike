defmodule DocumentOcr.Workers.Pipeline do
  alias DocumentOcr.{
    Documents,
    Repo,
    StorageAdapter,
    OCR,
    Extraction,
    ProcessingConfig,
    Validation
  }

  alias DocumentOcr.Documents.Processor
  alias DocumentOcr.Extraction.Appearance
  alias DocumentOcr.Workers
  require Logger

  def perform(stage, %Oban.Job{args: %{"document_id" => id, "run_id" => run_id}} = job) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, run_id} <- Ecto.UUID.cast(run_id) do
      perform_document(stage, id, run_id, job)
    else
      :error -> {:cancel, :invalid_job_arguments}
    end
  end

  # Legacy jobs cannot be safely attached to whichever run is current today.
  def perform(_stage, _job), do: {:cancel, :stale_run}

  defp perform_document(stage, id, run_id, job) do
    case Documents.get_document(id) do
      nil ->
        {:cancel, :document_not_found}

      %{status: "failed"} ->
        {:cancel, :document_not_active}

      %{run_id: ^run_id} = document ->
        run_unfinished(finished?(stage, document), stage, document, job)

      _ ->
        {:cancel, :stale_run}
    end
  rescue
    _ -> failure(id, run_id, job)
  end

  defp run_document(stage, document, job) do
    Logger.metadata(
      document_id: document.id,
      run_id: document.run_id,
      app_id: document.app_id,
      request_id: document.request_id,
      pipeline_version: document.pipeline_version,
      ocr_engine: document.ocr_engine,
      ocr_engine_version: document.ocr_engine_version,
      extractor_version: document.extractor_version
    )

    Logger.info("Processing document stage", stage: stage)

    case DocumentOcr.Telemetry.execute(stage, document, fn -> run(stage, document) end) do
      :ok -> :ok
      {:cancel, _} = cancelled -> cancelled
      {:error, :stale_run} -> {:cancel, :stale_run}
      {:error, reason} -> failure(document.id, document.run_id, job, reason)
      _ -> failure(document.id, document.run_id, job)
    end
  end

  defp run_unfinished(true, _stage, _document, _job), do: :ok
  defp run_unfinished(false, stage, document, job), do: run_document(stage, document, job)

  defp finished?(_stage, %{status: status})
       when status in ["completed", "rejected", "requires_confirmation"], do: true

  defp finished?(:preprocess, document),
    do: not is_nil(Documents.artifact(document, "preprocessed"))

  defp finished?(:ocr, document), do: not is_nil(Documents.artifact(document, "raw_ocr"))
  defp finished?(:extract, document), do: not is_nil(Documents.artifact(document, "extracted"))
  defp finished?(:validate, %{result: %{run_id: run}, run_id: run}), do: true
  defp finished?(_stage, _document), do: false

  defp failure(id, run_id, job, reason \\ :processing_failed) do
    # Keep external errors (which can contain identity data) out of Oban's error payload.
    case Repo.transaction(fn ->
           case Documents.lock(id) do
             nil ->
               {:cancel, :document_not_found}

             %{run_id: current_run_id} when current_run_id != run_id ->
               {:cancel, :stale_run}

             %{status: status} = document when status in ["pending", "processing"] ->
               {:ok, document} = Processor.start_processing(document)

               _ =
                 if job.attempt >= job.max_attempts do
                   {:ok, _} =
                     Processor.fail(
                       document,
                       failure_code(reason),
                       failure_message(reason)
                     )
                 end

               {:error, :processing_failed}

             _ ->
               :ok
           end
         end) do
      {:ok, result} -> result
      {:error, _} -> {:error, :processing_failed}
    end
  rescue
    _ -> {:error, :processing_failed}
  end

  defp failure_code(:timeout), do: "processing_timeout"
  defp failure_code(_), do: "processing_failed"
  defp failure_message(:timeout), do: "Processing stage timed out after retries"
  defp failure_message(_), do: "Processing stage exhausted retries"

  defp run(:preprocess, document) do
    with {:ok, _} <- ProcessingConfig.metadata(document),
         {:ok, document} <- Processor.start_processing(document),
         {:ok, images} <- load_images(document),
         :ok <-
           Documents.save_artifact_and_enqueue(
             document,
             "preprocessed",
             %{"images" => images},
             Workers.OcrDocument
           ),
         do: :ok
  end

  defp run(:ocr, document) do
    with %{data: %{"images" => images}} <- Documents.artifact(document, "preprocessed"),
         {:ok, outputs} <- extract_images(images, document),
         :ok <-
           Documents.save_artifact_and_enqueue(
             document,
             "raw_ocr",
             %{"images" => outputs},
             Workers.ExtractFields
           ),
         do: :ok
  end

  defp run(:extract, %{document_type: "auto"} = document) do
    %{data: %{"images" => images}} = Documents.artifact(document, "raw_ocr")
    lines = merge_outputs(images)

    case detect_type(lines) do
      nil ->
        with {:ok, _} <-
               Processor.fail(document, "unrecognized_document", "Document type not recognized"),
             do: {:cancel, :unrecognized_document}

      type ->
        extract(%{document | document_type: type}, lines)
    end
  end

  defp run(:extract, %{document_type: type} = document) when type in ["cnh", "rg"] do
    %{data: %{"images" => images}} = Documents.artifact(document, "raw_ocr")
    extract(document, merge_outputs(images))
  end

  defp run(:extract, _document), do: {:error, :unsupported_document_type}

  defp run(:validate, document) do
    %{data: data} = Documents.artifact(document, "extracted")

    with :ok <-
           Documents.save_result_and_enqueue(
             document,
             Validation.validate_result(data),
             Workers.CompleteDocument
           ),
         do: :ok
  end

  defp run(:complete, document) do
    outcome =
      case Validation.outcome(document.result.data) do
        :completed ->
          Processor.complete(document)

        :requires_confirmation ->
          Processor.require_confirmation(document, "Review extracted fields")

        :rejected ->
          Processor.reject(document)
      end

    case outcome do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp load_images(document) do
    document.images
    |> Enum.sort_by(&image_priority(&1.side))
    |> Enum.reduce_while({:ok, []}, fn image, {:ok, acc} ->
      case read_image(image) do
        {:ok, _bytes} -> {:cont, {:ok, acc ++ [%{"side" => image.side, "image_id" => image.id}]}}
        error -> {:halt, error}
      end
    end)
  end

  defp read_image(image) do
    case DocumentOcr.ExternalCall.run(
           fn -> load_image_bytes(image) end,
           Application.get_env(:document_ocr, :storage_timeout_ms, 5_000),
           Application.get_env(:document_ocr, :external_call_mode, :async)
         ) do
      {:ok, bytes} -> verify(image, bytes)
      {:error, :timeout} -> {:error, :timeout}
      _ -> {:error, :storage_failed}
    end
  end

  defp verify(%{blob: %AikeStorage.Blob{sha256: sha256}}, bytes) do
    if Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == sha256,
      do: {:ok, bytes},
      else: {:error, :storage_failed}
  end

  defp verify(_image, bytes), do: {:ok, bytes}

  defp image_bytes(%{"bytes" => encoded}, _document), do: Base.decode64(encoded)

  defp image_bytes(%{"image_id" => id}, document) do
    case Enum.find(document.images, &(&1.id == id)) do
      nil -> {:error, :storage_failed}
      image -> read_image(image)
    end
  end

  defp extract_images(images, document) do
    Enum.reduce_while(images, {:ok, []}, fn image, {:ok, acc} ->
      with {:ok, bytes} <- image_bytes(image, document),
           {:ok, output} <- ocr(bytes, document) do
        {:cont, {:ok, acc ++ [%{"side" => image["side"], "output" => output}]}}
      else
        {:error, :timeout} -> {:halt, {:error, :timeout}}
        {:error, :storage_failed} -> {:halt, {:error, :storage_failed}}
        _ -> {:halt, {:error, :ocr_failed}}
      end
    end)
  end

  defp ocr(bytes, document) do
    DocumentOcr.ExternalCall.run(
      fn -> OCR.extract(bytes, [document_type: document.document_type], document) end,
      Application.get_env(:document_ocr, :ocr_timeout_ms, 15_000),
      Application.get_env(:document_ocr, :external_call_mode, :async)
    )
  end

  defp load_image_bytes(%{blob: %AikeStorage.Blob{} = blob}), do: AikeStorage.Blobs.get(blob)
  defp load_image_bytes(%{source_key: key}), do: StorageAdapter.get(key)

  defp extract(document, lines) do
    with {:ok, data} <- Extraction.extract(lines, document) do
      data = describe(data, document, lines)
      Documents.save_artifact_and_enqueue(document, "extracted", data, Workers.ValidateFields)
    end
  end

  defp describe(%{"document" => described} = data, document, lines) do
    appearance =
      Appearance.describe(
        document.document_type,
        Enum.map(document.images, & &1.side),
        text(lines)
      )

    %{data | "document" => Map.merge(described, appearance)}
  end

  defp describe(data, _document, _lines), do: data

  defp text(%{"text" => lines}),
    do: Enum.map_join(lines, " ", &((is_map(&1) && &1["text"]) || ""))

  defp detect_type(lines) do
    case AikeVision.DocumentMarkers.analyze(text(lines)).type do
      :unknown -> nil
      type -> Atom.to_string(type)
    end
  end

  defp merge_outputs(images) do
    lines =
      images
      |> Enum.sort_by(&image_priority(&1["side"]))
      |> Enum.with_index()
      |> Enum.flat_map(fn {image, index} -> image_lines(image["output"], index) end)

    %{"text" => lines}
  end

  defp image_lines(%{"text" => lines}, index) when is_list(lines) do
    Enum.map(lines, fn
      %{"source" => source} = line -> %{line | "source" => "#{index}:#{source}"}
      line -> line
    end)
  end

  defp image_lines(_, _), do: [:invalid_output]

  defp image_priority("front"), do: 0
  defp image_priority("single"), do: 1
  defp image_priority(_), do: 2
end
