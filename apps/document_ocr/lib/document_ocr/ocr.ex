defmodule DocumentOcr.OCR do
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
