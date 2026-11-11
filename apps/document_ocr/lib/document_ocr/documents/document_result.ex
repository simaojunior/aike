defmodule DocumentOcr.Documents.DocumentResult do
  @moduledoc "Persisted OCR document domain data."
  use DocumentOcr, :model

  @type t :: %__MODULE__{}

  schema "document_results" do
    belongs_to(:document, DocumentOcr.Documents.Document)
    field(:run_id, :binary_id)
    field(:data, :map)
    field(:overall_confidence, :float)
    field(:pipeline_version, :string)
    field(:ocr_engine, :string)
    field(:ocr_engine_version, :string)
    field(:extractor_version, :string)
    timestamps(type: :utc_datetime_usec)
  end
end
