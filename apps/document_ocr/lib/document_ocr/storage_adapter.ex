defmodule DocumentOcr.StorageAdapter do
  @moduledoc """
  Reads a stored image through the configured storage.

  The storage module comes from the `:storage` key of the `:document_ocr` application.
  """
  def get(key), do: Application.fetch_env!(:document_ocr, :storage).get(key)
end
