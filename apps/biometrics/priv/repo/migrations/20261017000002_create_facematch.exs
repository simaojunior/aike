defmodule Biometrics.Repo.Migrations.CreateFacematch do
  use Ecto.Migration

  def change do
    create table(:blobs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:key, :string, null: false)
      add(:sha256, :string, null: false)
      add(:mime_type, :string, null: false)
      add(:byte_size, :bigint, null: false)
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(unique_index(:blobs, [:sha256]))
    create(unique_index(:blobs, [:key]))

    create table(:facematch_sessions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:app_id, :string, null: false)
      add(:external_id, :string, null: false)
      add(:status, :string, null: false, default: "pending")
      add(:engine, :string)
      add(:engine_version, :string)
      add(:decision, :text)
      add(:matched, :boolean)
      add(:similarity_score, :float)
      add(:selfie_face_detected, :boolean)
      add(:document_face_detected, :boolean)

      add(:selfie_blob_id, references(:blobs, type: :binary_id, on_delete: :restrict),
        null: false
      )

      add(:document_blob_id, references(:blobs, type: :binary_id, on_delete: :restrict),
        null: false
      )

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:facematch_sessions, [:app_id, :external_id]))
    create(index(:facematch_sessions, [:selfie_blob_id]))
    create(index(:facematch_sessions, [:document_blob_id]))

    create(
      index(
        :facematch_sessions,
        [:app_id, :selfie_blob_id, :document_blob_id, :engine, :engine_version],
        name: :facematch_sessions_reuse_index
      )
    )

    create table(:facematch_results, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:session_id, references(:facematch_sessions, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:data, :map, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:facematch_results, [:session_id]))

    create table(:processing_requests, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:service, :string, null: false)
      add(:company_id, :string, null: false)
      add(:key, :string, null: false)
      add(:fingerprint, :string, null: false)

      add(
        :facematch_session_id,
        references(:facematch_sessions, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:processing_requests, [:service, :company_id, :key]))
    create(index(:processing_requests, [:facematch_session_id]))

    create(
      constraint(:processing_requests, :processing_requests_facematch_only,
        check: "service = 'facematch'"
      )
    )
  end
end
