defmodule DocumentOcr.Repo.Migrations.AddProcessingRuns do
  use Ecto.Migration

  def up do
    alter table(:documents) do
      add(:run_id, :uuid, null: false, default: fragment("gen_random_uuid()"))
    end

    create(unique_index(:documents, [:id, :run_id]))

    for table <- [:document_artifacts, :document_results] do
      alter table(table) do
        add(:run_id, :uuid)
      end

      flush()

      execute(
        "UPDATE #{table} r SET run_id = d.run_id FROM documents d WHERE r.document_id = d.id"
      )

      alter table(table) do
        modify(:run_id, :uuid, null: false)
      end

      execute(
        "ALTER TABLE #{table} ADD CONSTRAINT #{table}_current_run_fkey FOREIGN KEY (document_id, run_id) REFERENCES documents (id, run_id) ON DELETE CASCADE"
      )
    end
  end

  def down do
    for table <- [:document_artifacts, :document_results] do
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_current_run_fkey")

      alter table(table) do
        remove(:run_id)
      end
    end

    drop(index(:documents, [:id, :run_id]))

    alter table(:documents) do
      remove(:run_id)
    end
  end
end
