defmodule DocumentOcr.Documents.DocumentImage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "document_images" do
    field(:side, :string)
    field(:source_key, :string)
    belongs_to(:document, DocumentOcr.Documents.Document)
    belongs_to(:blob, AikeStorage.Blob)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(image, attrs) do
    image
    |> cast(attrs, [:side, :source_key, :blob_id])
    |> validate_required([:side])
    |> validate_inclusion(:side, ["front", "back", "single"])
    |> unique_constraint([:document_id, :side])
  end
end
