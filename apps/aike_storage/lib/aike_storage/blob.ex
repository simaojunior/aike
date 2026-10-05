defmodule AikeStorage.Blob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}
  @type attrs :: map()

  schema "blobs" do
    field(:key, :string)
    field(:sha256, :string)
    field(:mime_type, :string)
    field(:byte_size, :integer)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @spec changeset(t(), attrs()) :: Ecto.Changeset.t()
  def changeset(blob, params) do
    blob
    |> cast(params, [:key, :sha256, :mime_type, :byte_size])
    |> validate_required([:key, :sha256, :mime_type, :byte_size])
    |> validate_length(:sha256, is: 64)
    |> unique_constraint(:sha256, message: "Duplicate file detected")
  end
end
