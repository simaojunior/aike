defmodule DocumentOcr.Extraction do
  alias DocumentOcr.ProcessingConfig

  def extract(raw_ocr, document) do
    with {:ok, module} <-
           ProcessingConfig.extractor(document.document_type, document.extractor_version) do
      module.extract(raw_ocr)
    end
  end
end
