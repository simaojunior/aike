defmodule DocumentOcr.Repo.Migrations.CreateBlobs do
  use Ecto.Migration

  def change do
    create table(:blobs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:key, :string, null: false)
      add(:sha256, :string, null: false)
      add(:mime_type, :string, null: false)
      add(:byte_size, :bigint, null: false)
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(unique_index(:blobs, [:sha256]))
    create(unique_index(:blobs, [:key]))
  end
end
