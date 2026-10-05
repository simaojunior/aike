defmodule DocumentClassifierWeb.ClassificationJSON do
  @moduledoc "JSON representations for classification responses."

  @spec upload(map(), Plug.Upload.t(), integer()) :: map()
  def upload(result, upload, started_at),
    do: DocumentClassifier.ClassificationResponse.from_upload(result, upload, started_at)

  @spec legacy(map()) :: map()
  def legacy(result), do: result
end
