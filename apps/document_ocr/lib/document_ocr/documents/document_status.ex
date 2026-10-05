defmodule DocumentOcr.Documents.DocumentStatus do
  defdelegate all(), to: KycCore.DocumentStatus
  defdelegate valid?(value), to: KycCore.DocumentStatus
end
