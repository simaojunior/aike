defmodule Biometrics.FacematchSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "facematch_sessions" do
    field(:app_id, :string)
    field(:external_id, :string)
    field(:status, :string, default: "pending")
    field(:decision, :string)
    field(:matched, :boolean)
    field(:similarity_score, :float)
    field(:selfie_face_detected, :boolean)
    field(:document_face_detected, :boolean)
    belongs_to(:selfie_blob, AikeStorage.Blob, foreign_key: :selfie_blob_id)
    belongs_to(:document_blob, AikeStorage.Blob, foreign_key: :document_blob_id)
    has_one(:result, Biometrics.FacematchResult, foreign_key: :session_id)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:app_id, :external_id, :selfie_blob_id, :document_blob_id, :status])
    |> validate_required([:app_id, :external_id, :selfie_blob_id, :document_blob_id])
  end
end
