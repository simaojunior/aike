defmodule Backoffice.Repo.Migrations.CreateCompanies do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    create table(:companies, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:active, :boolean, null: false, default: true)
      timestamps(type: :utc_datetime_usec)
    end

    alter table(:service_accounts) do
      add(:company_uuid, :binary_id)
    end

    execute("""
    INSERT INTO companies (id, name, active, inserted_at, updated_at)
    SELECT gen_random_uuid(), company_id, true, NOW(), NOW()
    FROM service_accounts
    WHERE company_id IS NOT NULL
    GROUP BY company_id
    """)

    execute("""
    UPDATE service_accounts AS accounts
    SET company_uuid = companies.id
    FROM companies
    WHERE companies.name = accounts.company_id
    """)

    drop(index(:service_accounts, [:company_id]))

    alter table(:service_accounts) do
      remove(:company_id)
    end

    rename(table(:service_accounts), :company_uuid, to: :company_id)

    alter table(:service_accounts) do
      modify(:company_id, references(:companies, column: :id, type: :binary_id), null: false)
    end

    create(index(:companies, [:active]))
    create(index(:service_accounts, [:company_id]))
  end

  def down do
    drop(index(:service_accounts, [:company_id]))

    alter table(:service_accounts) do
      add(:company_text, :string)
    end

    execute("""
    UPDATE service_accounts AS accounts
    SET company_text = companies.name
    FROM companies
    WHERE companies.id = accounts.company_id
    """)

    alter table(:service_accounts) do
      remove(:company_id)
    end

    rename(table(:service_accounts), :company_text, to: :company_id)

    alter table(:service_accounts) do
      modify(:company_id, :string, null: false)
    end

    create(index(:service_accounts, [:company_id]))
    drop(table(:companies))
  end
end
