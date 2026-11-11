defmodule DocumentOcr.Documents.DocumentImage do
  @moduledoc "Persisted OCR document domain data."
  use DocumentOcr, :model

  @type t :: %__MODULE__{}

  schema "document_images" do
    field(:side, :string)
    field(:source_key, :string)
    belongs_to(:document, DocumentOcr.Documents.Document)
    belongs_to(:blob, AikeStorage.Blob)
    timestamps(type: :utc_datetime_usec)
  end

  @type attrs :: map()
  @type changeset :: Ecto.Changeset.t(t())
  @spec changeset(t(), attrs()) :: changeset()
  def changeset(image, attrs) do
    image
    |> cast(attrs, [:side, :source_key, :blob_id])
    |> validate_required([:side])
    |> validate_inclusion(:side, ["front", "back", "single"])
    |> unique_constraint([:document_id, :side])
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:blob_id)
  end
end
