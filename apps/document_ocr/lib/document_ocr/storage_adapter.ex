defmodule DocumentOcr.StorageAdapter do
  def get(key), do: Application.fetch_env!(:document_ocr, :storage).get(key)
end
