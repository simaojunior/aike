defmodule DocumentOcr.Repo.Migrations.AllowAutomaticDocumentType do
  use Ecto.Migration

  def up do
    drop(constraint(:documents, :valid_type))
    create(constraint(:documents, :valid_type, check: "document_type IN ('cnh','rg','auto')"))
  end

  def down do
    drop(constraint(:documents, :valid_type))
    create(constraint(:documents, :valid_type, check: "document_type IN ('cnh','rg')"))
  end
end
