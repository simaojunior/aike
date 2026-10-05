defmodule DocumentOcr.Repo.Migrations.AddIdempotencyKey do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add(:idempotency_key, :string)
    end

    create(unique_index(:documents, [:app_id, :idempotency_key]))
  end
end
