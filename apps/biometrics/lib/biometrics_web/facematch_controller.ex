defmodule BiometricsWeb.FacematchController do
  use BiometricsWeb, :controller
  alias BiometricsWeb.FacematchJSON
  alias KycCore.JsonKeyFormatter

  plug(BiometricsWeb.ValidateParams,
    create: &BiometricsWeb.Schemas.FacematchParams.create/1
  )

  def create(conn, %{"app_id" => app, "external_id" => external, "selfie_image" => selfie, "document_image" => document}) do
    with {:ok, selfie_blob} <- store(selfie), {:ok, document_blob} <- store(document),
         {:ok, %{session: session}} <- Biometrics.Facematches.create(%{app_id: app, external_id: external, selfie_blob_id: selfie_blob.id, document_blob_id: document_blob.id}) do
      conn |> put_status(202) |> json(JsonKeyFormatter.format(%{id: session.id, status: session.status}))
    else
      _ -> conn |> put_status(422) |> json(%{error: "invalid_request"})
    end
  end

  def create(conn, _), do: conn |> put_status(422) |> json(%{error: "invalid_request"})

  def show(conn, %{"id" => id}) do
    case Biometrics.Facematches.get(id) do
      nil -> conn |> put_status(404) |> json(%{error: "not_found"})
      session -> json(conn, JsonKeyFormatter.format(FacematchJSON.data(session)))
    end
  end

  defp store(%Plug.Upload{} = upload) do
    with {:ok, data} <- File.read(upload.path), {:ok, blob} <- AikeStorage.Blobs.put(data, upload.filename, upload.content_type, repo: Biometrics.Repo) do
      {:ok, blob}
    end
  end
  defp store(_), do: {:error, :invalid_upload}
end
