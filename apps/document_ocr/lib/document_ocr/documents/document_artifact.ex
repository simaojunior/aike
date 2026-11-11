defmodule DocumentOcr.Documents.DocumentArtifact do
  @moduledoc "Persisted OCR document domain data."
  use DocumentOcr, :model

  @type t :: %__MODULE__{}

  schema "document_artifacts" do
    belongs_to(:document, DocumentOcr.Documents.Document)
    field(:run_id, :binary_id)
    field(:kind, :string)
    field(:data, :map)
    timestamps(type: :utc_datetime_usec)
  end
end
