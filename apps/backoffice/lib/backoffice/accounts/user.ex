defmodule Backoffice.Accounts.User do
  @moduledoc "Human identity; platform privileges are explicit and independent of company membership."
  use Backoffice, :model
  @roles ~w(platform_admin company_admin company_user)a
  @required ~w(company_id email name role)a
  @optional []
  @type t :: %__MODULE__{}
  @type attrs :: map()
  @type changeset :: Ecto.Changeset.t(t())
  @derive {Inspect, except: [:password_hash]}
  schema "backoffice_users" do
    belongs_to(:company, Backoffice.Tenants.Company)
    field(:email, :string)
    field(:name, :string)
    field(:role, Ecto.Enum, values: @roles, default: :company_user)
    field(:password_hash, :string, redact: true)
    field(:active, :boolean, default: true)
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), attrs()) :: changeset()
  def changeset(user, attrs) do
    user
    |> cast(attrs, @required ++ @optional)
    |> update_change(:email, &normalize_email/1)
    |> validate_required(@required)
    |> validate_format(:email, ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/u)
    |> validate_length(:email, max: 254)
    |> validate_length(:name, min: 2, max: 160)
    |> unique_constraint(:email)
    |> foreign_key_constraint(:company_id)
    |> check_constraint(:email, name: :backoffice_users_email_normalized)
    |> check_constraint(:role, name: :backoffice_users_role_check)
  end

  @spec access_changeset(t(), attrs()) :: changeset()
  def access_changeset(user, attrs),
    do: cast(user, attrs, [:role, :active]) |> validate_required([:role, :active])

  @spec normalize_email(term()) :: String.t()
  def normalize_email(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  def normalize_email(_), do: ""
end
