defmodule Backoffice.Repo.Migrations.CreateServiceAccounts do
  use Ecto.Migration

  def change do
    create table(:service_accounts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:account_id, :string, null: false)
      add(:secret_hash, :string, null: false)
      add(:scopes, {:array, :string}, null: false, default: [])
      add(:company_id, :string, null: false)
      add(:name, :string, null: false)
      add(:active, :boolean, null: false, default: true)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:service_accounts, [:account_id]))
    create(index(:service_accounts, [:company_id]))
  end
end
