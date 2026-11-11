defmodule DocumentOcr.Repo.Migrations.CreateWebhooks do
  use Ecto.Migration

  def change do
    create table(:webhook_endpoints, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:company_id, :string, null: false)
      add(:url, :text, null: false)
      add(:active, :boolean, null: false, default: true)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:webhook_endpoints, [:company_id]))

    create table(:webhook_deliveries, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:endpoint_id, references(:webhook_endpoints, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:run_id, :binary_id, null: false)
      add(:event_type, :string, null: false)
      add(:payload, :map, null: false)
      add(:status, :string, null: false, default: "pending")
      add(:attempts, :integer, null: false, default: 0)
      add(:last_status_code, :integer)
      add(:delivered_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:webhook_deliveries, [:endpoint_id]))
    create(index(:webhook_deliveries, [:document_id]))

    create(
      unique_index(:webhook_deliveries, [:endpoint_id, :document_id, :run_id, :event_type],
        name: :webhook_deliveries_one_event_per_run
      )
    )

    create(
      constraint(:webhook_deliveries, :valid_delivery_status,
        check: "status IN ('pending','delivered','failed')"
      )
    )
  end
end
