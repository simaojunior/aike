defmodule DocumentOcr.Documents.DocumentArtifact do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "document_artifacts" do
    belongs_to(:document, DocumentOcr.Documents.Document)
    field(:run_id, :binary_id)
    field(:kind, :string)
    field(:data, :map)
    timestamps(type: :utc_datetime_usec)
  end
end
