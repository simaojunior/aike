defmodule Biometrics.BlobOwner do
  @moduledoc """
  The biometrics service as owner of its blobs: `Biometrics.Repo`, the `facematch` folder
  and the selfie and document columns of facematch sessions.

  ## Examples

      AikeStorage.Ingestion.run(Biometrics.BlobOwner.owner(), uploads, create)
  """

  @doc """
  Returns the storage owner of the biometrics service.

  ## Returns
    - an `AikeStorage.Owner`
  """
  @spec owner() :: AikeStorage.Owner.t()
  def owner do
    AikeStorage.Owner.new(
      repo: Biometrics.Repo,
      folder: "facematch",
      blob_references: [
        {"facematch_sessions", "selfie_blob_id"},
        {"facematch_sessions", "document_blob_id"}
      ]
    )
  end
end
