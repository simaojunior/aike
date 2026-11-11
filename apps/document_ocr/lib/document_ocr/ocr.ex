defmodule DocumentOcr.OCR do
  @moduledoc """
  Reads text from an image with the configured OCR engine.

  The engine and its version come from the processing profile, so a document keeps the
  engine version that it captured.
  """
  alias DocumentOcr.ProcessingConfig

  def extract(image, opts \\ []) do
    with {:ok, profile} <- ProcessingConfig.capture() do
      extract(image, opts, profile)
    end
  end

  def extract(image, opts, profile) do
    with {:ok, module} <- ProcessingConfig.engine(profile) do
      module.extract(image, Keyword.put(opts, :engine_version, profile.ocr_engine_version))
    end
  end
end
