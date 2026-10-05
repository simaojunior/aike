defmodule DocumentOcr.Repo.Migrations.AddDecisions do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add(:decision, :text)
    end

    create(
      constraint(:documents, :valid_decision,
        check: "decision IS NULL OR decision IN ('approved','rejected','manual_review')"
      )
    )

    alter table(:facematch_sessions) do
      add(:decision, :text)
      add(:matched, :boolean)
      add(:similarity_score, :float)
      add(:selfie_face_detected, :boolean)
      add(:document_face_detected, :boolean)
    end
  end
end
