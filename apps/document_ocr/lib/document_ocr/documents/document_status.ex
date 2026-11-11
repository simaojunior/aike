defmodule DocumentOcr.Documents.DocumentStatus do
  @moduledoc """
  Status values of an OCR document.

  It delegates to `KycCore.DocumentStatus`.
  """
  defdelegate all(), to: KycCore.DocumentStatus
  defdelegate valid?(value), to: KycCore.DocumentStatus
end
