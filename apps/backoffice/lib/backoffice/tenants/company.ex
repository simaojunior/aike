defmodule Backoffice.Tenants.Company do
  @moduledoc "Tenant company that owns Aike service accounts."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{id: Ecto.UUID.t() | nil, name: String.t() | nil, active: boolean()}

  schema "companies" do
    field(:name, :string)
    field(:active, :boolean, default: true)
    field(:is_platform, :boolean, default: false)
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(company, attrs) do
    company
    |> cast(attrs, [:name, :active])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 160)
    |> unique_constraint(:id)
  end
end
