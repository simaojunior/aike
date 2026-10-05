defmodule DocumentClassifier.Classifications do
  alias DocumentClassifier.Result

  def classify(%{"source" => %{"type" => "object_storage", "key" => key}})
      when is_binary(key) and byte_size(key) > 0 and byte_size(key) <= 1024 do
    if String.trim(key) == "", do: {:error, :invalid_request}, else: classify_key(key)
  end

  def classify(%Plug.Upload{} = upload), do: classify_upload(upload)
  def classify(%{"image" => %Plug.Upload{} = upload}), do: classify_upload(upload)

  def classify(_), do: {:error, :invalid_request}

  defp classify_key(key) do
    storage = Application.fetch_env!(:document_classifier, :storage)
    engine = Application.fetch_env!(:document_classifier, :engine)

    with {:ok, image} when is_binary(image) <- storage.get(key),
         {:ok, result} <- engine.classify(image, []),
         {:ok, result} <- Result.validate(result) do
      {:ok, result}
    else
      _ -> {:error, :service_unavailable}
    end
  rescue
    # Adapter messages may contain keys, credentials or image data.
    _ -> {:error, :service_unavailable}
  end

  defp classify_upload(%Plug.Upload{path: path}) do
    with {:ok, image} <- File.read(path),
         {:ok, result} <- classify_binary(image) do
      {:ok, result}
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp classify_binary(image) do
    engine = Application.fetch_env!(:document_classifier, :engine)

    with {:ok, result} <- engine.classify(image, []),
         {:ok, result} <- Result.validate(result) do
      {:ok, result}
    else
      _ -> {:error, :service_unavailable}
    end
  end
end
