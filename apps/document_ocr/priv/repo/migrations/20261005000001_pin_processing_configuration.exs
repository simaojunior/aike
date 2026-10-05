defmodule DocumentOcr.Repo.Migrations.PinProcessingConfiguration do
  use Ecto.Migration

  def change do
    # Nullable only for legacy documents: their original configuration was not recorded.
    # Do not infer it from the currently deployed engine or rewrite historical results.
    alter table(:documents) do
      add(:ocr_engine, :text)
      add(:ocr_engine_version, :text)
      add(:extractor_version, :text)
    end

    create(
      constraint(:documents, :complete_processing_configuration,
        check: """
        (ocr_engine IS NULL AND ocr_engine_version IS NULL AND extractor_version IS NULL)
        OR (ocr_engine IS NOT NULL AND ocr_engine_version IS NOT NULL AND extractor_version IS NOT NULL
            AND length(trim(ocr_engine)) > 0 AND length(trim(ocr_engine_version)) > 0
            AND length(trim(extractor_version)) > 0)
        """
      )
    )
  end
end
