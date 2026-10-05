defmodule DocumentOcr.Repo.Migrations.CreateCompanies do
  use Ecto.Migration

  def change do
    create table(:companies, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:name, :string, null: false)
      add(:active, :boolean, null: false, default: true)
      timestamps(type: :utc_datetime_usec)
    end

    alter table(:service_accounts) do
      modify(:company_id, references(:companies, column: :id, type: :string), null: false)
    end

    create(index(:companies, [:active]))
  end
end
