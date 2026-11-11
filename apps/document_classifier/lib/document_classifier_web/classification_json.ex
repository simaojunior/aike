defmodule DocumentClassifierWeb.ClassificationJSON do
  @moduledoc """
  The classification response. Multipart and JSON (base64) requests get the same envelope,
  see `DocumentClassifier.ClassificationResponse`.
  """

  @doc """
  Renders a classification.

  ## Parameters
    - result: the engine result
    - source: the uploaded file, or `{:image, base64}`
    - started_at: monotonic start time in milliseconds

  ## Returns
    - the ordered response body
  """
  @spec render(map(), DocumentClassifier.ClassificationResponse.source(), integer()) ::
          Jason.OrderedObject.t()
  def render(result, source, started_at),
    do: DocumentClassifier.ClassificationResponse.build(result, source, started_at)
end
