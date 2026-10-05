defmodule DocumentOcr.Repo.Migrations.AddBlobToDocumentImages do
  use Ecto.Migration

  def change do
    alter table(:document_images) do
      add(:blob_id, references(:blobs, type: :binary_id, on_delete: :restrict))
    end

    create(index(:document_images, [:blob_id]))
  end
end
