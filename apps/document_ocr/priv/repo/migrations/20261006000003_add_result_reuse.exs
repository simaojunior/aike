defmodule DocumentOcr.Repo.Migrations.AddResultReuse do
  use Ecto.Migration

  def change do
    create table(:classification_results, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:company_id, :string, null: false)
      add(:sha256, :string, null: false)
      add(:engine, :string, null: false)
      add(:engine_version, :string, null: false)
      add(:data, :map, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:classification_results, [:company_id, :sha256, :engine, :engine_version],
        name: :classification_results_identity_index
      )
    )

    alter table(:facematch_sessions) do
      add(:engine, :string)
      add(:engine_version, :string)
    end

    create(
      index(
        :facematch_sessions,
        [:app_id, :selfie_blob_id, :document_blob_id, :engine, :engine_version],
        name: :facematch_sessions_reuse_index
      )
    )
  end
end
