defmodule KycCore.Tenants.Company do
  @moduledoc "Tenant company that owns Aike service accounts."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @type t :: %__MODULE__{id: String.t() | nil, name: String.t() | nil, active: boolean()}

  schema "companies" do
    field(:name, :string)
    field(:active, :boolean, default: true)
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(company, attrs) do
    company
    |> cast(attrs, [:id, :name, :active])
    |> validate_required([:id, :name])
    |> validate_length(:id, min: 2, max: 128)
    |> validate_length(:name, min: 2, max: 160)
    |> unique_constraint(:id)
  end
end
