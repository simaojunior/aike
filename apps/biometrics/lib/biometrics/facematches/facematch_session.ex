defmodule Biometrics.Facematches.FacematchSession do
  @moduledoc "Persisted facematch domain data."
  use Biometrics, :model
  @type t :: %__MODULE__{}
  @type attrs :: map()
  @type changeset :: Ecto.Changeset.t(t())

  schema "facematch_sessions" do
    field(:app_id, :string)
    field(:external_id, :string)
    field(:engine, :string)
    field(:engine_version, :string)
    field(:status, :string, default: "pending")
    field(:decision, :string)
    field(:matched, :boolean)
    field(:similarity_score, :float)
    field(:selfie_face_detected, :boolean)
    field(:document_face_detected, :boolean)
    belongs_to(:selfie_blob, AikeStorage.Blob, foreign_key: :selfie_blob_id)
    belongs_to(:document_blob, AikeStorage.Blob, foreign_key: :document_blob_id)
    has_one(:result, Biometrics.Facematches.FacematchResult, foreign_key: :session_id)
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), attrs()) :: changeset()
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:app_id, :external_id, :selfie_blob_id, :document_blob_id, :status])
    |> validate_required([:app_id, :external_id, :selfie_blob_id, :document_blob_id])
  end
end
