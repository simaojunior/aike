defmodule KycCore.Auth.ServiceAccount do
  use Ecto.Schema
  import Ecto.Changeset
  alias KycCore.Auth.Scopes

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
    |> validate_length(:account_id, min: 3, max: 128)
    |> validate_length(:name, min: 2, max: 160)
    |> validate_change(:scopes, &validate_scopes/2)
    |> unique_constraint(:account_id)
  end

  defp validate_scopes(:scopes, scopes) when is_list(scopes) do
    case Enum.find(scopes, &(not Scopes.valid?(&1))) do
      nil -> []
      invalid -> [scopes: "contains unsupported scope #{invalid}"]
    end
  end

  defp validate_scopes(:scopes, _scopes), do: [scopes: "must be a list"]
end
