defmodule KycCore.Auth.ServiceAccount do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}
  @type attrs :: map()

  schema "service_accounts" do
    field(:account_id, :string)
    field(:secret_hash, :string)
    field(:scopes, {:array, :string}, default: [])
    field(:company_id, :string)
    field(:name, :string)
    field(:active, :boolean, default: true)
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), attrs()) :: Ecto.Changeset.t()
  def changeset(account, attrs) do
    account
    |> cast(attrs, [:account_id, :secret_hash, :scopes, :company_id, :name, :active])
    |> validate_required([:account_id, :secret_hash, :scopes, :company_id, :name])
    |> unique_constraint(:account_id)
  end
end
