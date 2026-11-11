defmodule DocumentClassifier.Classifications do
  @moduledoc "Synchronously classifies direct document bytes without persistence."
  alias DocumentClassifier.Result

  @file_errors [
    :invalid_request,
    :unsupported_image,
    :image_too_large,
    :unsupported_page_count,
    :file_too_large
  ]
  require Logger

  @spec classify(map() | Plug.Upload.t(), String.t() | nil) :: {:ok, map()} | {:error, atom()}
  def classify(input, company_id \\ nil)

  def classify(%{"image" => encoded}, company_id) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, image} when byte_size(image) > 0 -> classify_binary(image, company_id)
      _ -> {:error, :invalid_request}
    end
  end

  def classify(%Plug.Upload{} = upload, company_id), do: classify_upload(upload, company_id)

  def classify(%{"image" => %Plug.Upload{} = upload}, company_id),
    do: classify_upload(upload, company_id)

  def classify(_, _company_id), do: {:error, :invalid_request}

  defp classify_upload(%Plug.Upload{path: path}, company_id) do
    case File.read(path) do
      {:ok, image} when byte_size(image) > 0 -> classify_binary(image, company_id)
      _ -> {:error, :invalid_request}
    end
  end

  defp classify_binary(image, _company_id) do
    engine = Application.fetch_env!(:document_classifier, :engine)

    with {:engine, {:ok, result}} <- {:engine, engine.classify(image, [])},
         {:result, {:ok, result}} <- {:result, Result.validate(result)} do
      {:ok, result}
    else
      {:engine, {:error, reason}} when reason in @file_errors -> {:error, reason}
      {:engine, {:error, :overloaded}} -> {:error, :overloaded}
      {:engine, _} -> unavailable(:engine_failed)
      {:result, _} -> unavailable(:invalid_engine_result)
    end
  rescue
    _ -> unavailable(:unexpected_exception)
  end

  defp unavailable(reason) do
    Logger.error("Document classification failed: #{reason}", event: "classifier.failed")
    {:error, :service_unavailable}
  end
end
