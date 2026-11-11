defmodule Backoffice.Repo.Migrations.AddBackofficeIdentity do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add(:is_platform, :boolean, null: false, default: false)
    end

    create(unique_index(:companies, [:is_platform], where: "is_platform = true"))

    create table(:backoffice_users, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:company_id, references(:companies, type: :binary_id), null: false)
      add(:email, :string, null: false)
      add(:name, :string, null: false)
      add(:role, :string, null: false)
      add(:password_hash, :text, null: false)
      add(:active, :boolean, null: false, default: true)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:backoffice_users, [:email]))
    create(index(:backoffice_users, [:company_id]))

    create(
      constraint(:backoffice_users, :backoffice_users_role_check,
        check: "role IN ('platform_admin', 'company_admin', 'company_user')"
      )
    )

    create(
      constraint(:backoffice_users, :backoffice_users_email_normalized,
        check: "email = lower(trim(email))"
      )
    )

    create table(:backoffice_sessions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:user_id, references(:backoffice_users, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:expires_at, :utc_datetime_usec, null: false)
      add(:revoked_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:backoffice_sessions, [:user_id]))
    create(index(:backoffice_sessions, [:expires_at]))

    create table(:backoffice_tokens, primary_key: false) do
      add(:token_hash, :binary, primary_key: true)

      add(:session_id, references(:backoffice_sessions, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:kind, :string, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:used_at, :utc_datetime_usec)
    end

    create(index(:backoffice_tokens, [:session_id]))

    create(
      constraint(:backoffice_tokens, :backoffice_tokens_kind_check,
        check: "kind IN ('access', 'refresh')"
      )
    )

    create table(:backoffice_auth_limits, primary_key: false) do
      add(:key, :binary, primary_key: true)
      add(:attempts, :integer, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
    end

    create(index(:backoffice_auth_limits, [:expires_at]))

    create table(:backoffice_audit_events, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:actor_id, :binary_id)
      add(:company_id, :binary_id)
      add(:action, :string, null: false)
      add(:target_id, :binary_id)
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:backoffice_audit_events, [:company_id, :inserted_at]))
  end
end
