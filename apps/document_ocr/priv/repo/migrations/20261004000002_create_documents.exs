defmodule DocumentOcr.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:app_id, :text, null: false)
      add(:external_id, :text, null: false)
      add(:document_type, :text, null: false)
      add(:country, :text, null: false)
      add(:status, :text, null: false, default: "pending")
      add(:pipeline_version, :text, null: false)
      add(:request_id, :text, null: false)
      add(:error_code, :text)
      add(:error_message, :text)
      timestamps(type: :utc_datetime_usec)
    end

    create(
      constraint(:documents, :valid_status,
        check:
          "status IN ('pending','processing','completed','requires_confirmation','failed','rejected')"
      )
    )

    create(constraint(:documents, :valid_type, check: "document_type IN ('cnh','rg')"))
    create(constraint(:documents, :valid_country, check: "country = 'BR'"))
    create(index(:documents, [:status]))
    create(index(:documents, [:app_id, :external_id]))

    create table(:document_images, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:document_id, references(:documents, type: :uuid, on_delete: :delete_all), null: false)
      add(:side, :text, null: false)
      add(:source_key, :text, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:document_images, [:document_id, :side]))
    create(constraint(:document_images, :valid_side, check: "side IN ('front','back','single')"))

    create table(:document_artifacts, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:document_id, references(:documents, type: :uuid, on_delete: :delete_all), null: false)
      add(:kind, :text, null: false)
      add(:data, :map, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:document_artifacts, [:document_id, :kind]))

    create table(:document_results, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:document_id, references(:documents, type: :uuid, on_delete: :delete_all), null: false)
      add(:data, :map, null: false)
      add(:overall_confidence, :float, null: false)
      add(:pipeline_version, :text, null: false)
      add(:ocr_engine, :text, null: false)
      add(:ocr_engine_version, :text, null: false)
      add(:extractor_version, :text, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:document_results, [:document_id]))
  end
end
