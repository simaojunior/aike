defmodule DocumentOcr.Repo.Migrations.AddProcessingRequests do
  use Ecto.Migration

  def change do
    create table(:processing_requests, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:service, :string, null: false)
      add(:company_id, :string, null: false)
      add(:key, :string, null: false)
      add(:fingerprint, :string, null: false)
      add(:document_id, references(:documents, type: :binary_id, on_delete: :delete_all))

      add(
        :facematch_session_id,
        references(:facematch_sessions, type: :binary_id, on_delete: :delete_all)
      )

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:processing_requests, [:service, :company_id, :key]))
    create(index(:processing_requests, [:document_id]))
    create(index(:processing_requests, [:facematch_session_id]))

    create(
      constraint(:processing_requests, :processing_requests_resource,
        check:
          "(service = 'ocr' AND document_id IS NOT NULL AND facematch_session_id IS NULL) OR (service = 'facematch' AND document_id IS NULL AND facematch_session_id IS NOT NULL)"
      )
    )
  end
end
