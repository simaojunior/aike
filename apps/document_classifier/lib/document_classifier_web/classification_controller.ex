defmodule DocumentClassifierWeb.ClassificationController do
  @moduledoc """
  `POST /v1/classifications`: classifies one image or PDF sent as multipart (`file` or
  `image`) or as JSON base64 (`image`). The answer is synchronous.
  """
  use DocumentClassifierWeb, :controller
  action_fallback(DocumentClassifierWeb.FallbackController)

  alias DocumentClassifierWeb.ClassificationJSON
  alias DocumentClassifierWeb.Schemas.ClassificationParams

  plug(DocumentClassifierWeb.ValidateParams,
    create: &ClassificationParams.create/1
  )

  def create(conn, params) do
    started_at = System.monotonic_time(:millisecond)
    {input, source} = resolve_input(params)

    with {:ok, result} <-
           DocumentClassifier.Classifications.classify(input, conn.assigns[:company_id]) do
      json(conn, ClassificationJSON.render(result, source, started_at))
    end
  end

  defp resolve_input(%{"file" => %Plug.Upload{} = upload}), do: {upload, upload}
  defp resolve_input(%{"image" => %Plug.Upload{} = upload}), do: {upload, upload}
  defp resolve_input(%{"image" => encoded} = params), do: {params, {:image, encoded}}
end
