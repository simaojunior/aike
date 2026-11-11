defmodule DocumentOcr.BlobOwner do
  @moduledoc """
  The OCR service as owner of its blobs: `DocumentOcr.Repo`, the `kyc_documents` folder
  and the document image columns that reference them.

  ## Examples

      AikeStorage.Ingestion.run(DocumentOcr.BlobOwner.owner(), uploads, create)
  """

  @doc """
  Returns the storage owner of the OCR service.

  ## Returns
    - an `AikeStorage.Owner`
  """
  @spec owner() :: AikeStorage.Owner.t()
  def owner do
    AikeStorage.Owner.new(
      repo: DocumentOcr.Repo,
      folder: "kyc_documents",
      blob_references: [{"document_images", "blob_id"}],
      key_references: [{"document_images", "source_key"}]
    )
  end
end
