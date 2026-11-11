defmodule DocumentOcr.Extraction do
  @moduledoc """
  Extracts structured fields from the OCR text of a document.

  The extractor module comes from the extractor version that the document captured.
  """
  alias DocumentOcr.ProcessingConfig

  def extract(raw_ocr, document) do
    with {:ok, module} <-
           ProcessingConfig.extractor(document.document_type, document.extractor_version) do
      module.extract(raw_ocr)
    end
  end
end
