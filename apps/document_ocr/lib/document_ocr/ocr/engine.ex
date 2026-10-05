defmodule DocumentOcr.OCR.Engine do
  @moduledoc """
  Adapter boundary: receive image bytes and return raw OCR without domain persistence.

  The pipeline passes :document_type and the captured :engine_version in opts.
  An adapter must honor the registered version or return an error; it must not silently
  substitute a different model. Output for the current CNH extractor is a string-keyed
  map with a "text" list of %{"text" => string, "confidence" => number_in_0_to_1}.
  No storage, Ecto, Oban or controller calls belong in an adapter.
  """
  @callback extract(binary(), keyword()) :: {:ok, map()} | {:error, term()}
end
