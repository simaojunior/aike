defmodule DocumentOcr.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @type t :: %__MODULE__{}
  @type attrs :: map()

  schema "documents" do
    field(:app_id, :string)
    field(:external_id, :string)
    field(:document_type, :string)
    field(:country, :string)
    field(:status, :string, default: "pending")
    field(:decision, :string)
    field(:run_id, :binary_id)
    field(:pipeline_version, :string)
    field(:ocr_engine, :string)
    field(:ocr_engine_version, :string)
    field(:extractor_version, :string)
    field(:request_id, :string)
    field(:idempotency_key, :string)
    field(:error_code, :string)
    field(:error_message, :string)
    has_many(:images, DocumentOcr.Documents.DocumentImage)
    has_one(:result, DocumentOcr.Documents.DocumentResult)
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), attrs()) :: Ecto.Changeset.t()
  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :app_id,
      :external_id,
      :document_type,
      :country,
      :request_id,
      :idempotency_key
    ])
    |> validate_required([
      :app_id,
      :external_id,
      :document_type,
      :country,
      :request_id
    ])
    |> validate_inclusion(:document_type, ["cnh"])
    |> validate_inclusion(:country, ["BR"])
    |> validate_length(:idempotency_key, max: 256)
    |> cast_assoc(:images, required: true)
    |> validate_length(:images, min: 1, max: 2)
  end
end
