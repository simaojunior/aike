defmodule DocumentOcr.Repo.Migrations.CreateFacematch do
  use Ecto.Migration

  def change do
    create table(:facematch_sessions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:app_id, :string, null: false)
      add(:external_id, :string, null: false)
      add(:status, :string, null: false, default: "pending")

      add(:selfie_blob_id, references(:blobs, type: :binary_id, on_delete: :restrict),
        null: false
      )

      add(:document_blob_id, references(:blobs, type: :binary_id, on_delete: :restrict),
        null: false
      )

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:facematch_sessions, [:app_id, :external_id]))

    create table(:facematch_results, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:session_id, references(:facematch_sessions, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:data, :map, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:facematch_results, [:session_id]))
  end
end
