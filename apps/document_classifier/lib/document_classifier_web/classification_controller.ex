defmodule DocumentClassifierWeb.ClassificationController do
  use DocumentClassifierWeb, :controller
  alias DocumentClassifierWeb.ClassificationJSON
  alias KycCore.JsonKeyFormatter

  plug(DocumentClassifierWeb.ValidateParams,
    create: &DocumentClassifierWeb.Schemas.ClassificationParams.create/1
  )

  require Logger

  def create(conn, params) do
    upload = params["file"] || params["image"]
    input = if match?(%Plug.Upload{}, upload), do: upload, else: params
    started_at = System.monotonic_time(:millisecond)

    case DocumentClassifier.Classifications.classify(input) do
      {:ok, result} ->
        response =
          if match?(%Plug.Upload{}, upload),
            do: ClassificationJSON.upload(result, upload, started_at),
            else: ClassificationJSON.legacy(result)

        json(conn, JsonKeyFormatter.format(response))

      {:error, :invalid_request} ->
        conn |> put_status(422) |> json(%{error: "invalid_request"})

      {:error, :service_unavailable} ->
        Logger.warning("Classification service unavailable")
        conn |> put_status(503) |> json(%{error: "service_unavailable"})
    end
  end
end
