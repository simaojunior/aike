defmodule Biometrics.Facematches do
  @moduledoc "Facematch ingestion and completed-result reuse."
  alias Biometrics.Facematches.{FacematchRepo, FacematchSession}
  @spec get(Ecto.UUID.t()) :: FacematchSession.t() | nil
  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> FacematchRepo.get(uuid)
      _ -> nil
    end
  end

  @spec get(String.t() | nil, term()) :: FacematchSession.t() | nil
  def get(nil, _id), do: nil

  def get(app_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> FacematchRepo.get(app_id, uuid)
      _ -> nil
    end
  end

  @spec create(map()) :: {:ok, map()} | {:error, term()} | {:error, term(), term(), map()}
  def create(%{__struct__: _}), do: {:error, :invalid_request}
  def create(attrs), do: FacematchRepo.create(attrs)
  @spec complete(FacematchSession.t(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate complete(session, data), to: FacematchRepo

  @spec process(String.t(), non_neg_integer(), pos_integer(), (FacematchSession.t() -> term())) ::
          term()
  defdelegate process(id, attempt, maximum, fun), to: Biometrics.Facematches.Processing, as: :run

  @spec create_from_uploads(map(), term(), term()) :: term()
  def create_from_uploads(attrs, selfie, document) do
    with {:ok, selfie} <- read_upload(selfie),
         {:ok, document} <- read_upload(document) do
      AikeStorage.Ingestion.run(Biometrics.BlobOwner.owner(), [selfie, document], fn [
                                                                                       selfie_blob,
                                                                                       document_blob
                                                                                     ] ->
        create(
          Map.merge(attrs, %{selfie_blob_id: selfie_blob.id, document_blob_id: document_blob.id})
        )
      end)
    end
  end

  defp read_upload(%Plug.Upload{} = upload) do
    case File.read(upload.path) do
      {:ok, bytes} when byte_size(bytes) > 0 ->
        {:ok, %{binary: bytes, filename: upload.filename, mime_type: upload.content_type}}

      _ ->
        {:error, :invalid_upload}
    end
  end

  defp read_upload(_), do: {:error, :invalid_upload}
end
