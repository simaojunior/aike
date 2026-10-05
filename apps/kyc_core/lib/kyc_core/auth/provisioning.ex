defmodule KycCore.Auth.Provisioning do
  @moduledoc "Creates tenant companies and one-time service credentials."

  alias KycCore.Auth.{Secret, ServiceAccount}
  alias KycCore.Tenants.Company

  @type repo :: module()
  @type provisioned_account :: {ServiceAccount.t(), String.t()}

  @spec create_company(repo(), map()) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def create_company(repo, attrs) do
    %Company{}
    |> Company.changeset(attrs)
    |> repo.insert()
  end

  @spec create_service_account(repo(), Company.t() | String.t(), map()) ::
          {:ok, provisioned_account()} | {:error, :company_not_found | Ecto.Changeset.t()}
  def create_service_account(repo, company_or_id, attrs)

  def create_service_account(repo, %Company{} = company, attrs) do
    insert_service_account(repo, company, attrs)
  end

  def create_service_account(repo, company_id, attrs) when is_binary(company_id) do
    case repo.get(Company, company_id) do
      nil -> {:error, :company_not_found}
      company -> insert_service_account(repo, company, attrs)
    end
  end

  defp insert_service_account(repo, company, attrs) do
    secret = generate_secret()

    account_id =
      Map.get(attrs, :account_id) || Map.get(attrs, "account_id") ||
        generate_account_id(company.id)

    account_attrs =
      attrs
      |> Map.put(:account_id, account_id)
      |> Map.put(:company_id, company.id)
      |> Map.put(:secret_hash, Secret.hash(secret))

    case %ServiceAccount{} |> ServiceAccount.changeset(account_attrs) |> repo.insert() do
      {:ok, account} -> {:ok, {account, secret}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp generate_account_id(company_id) do
    "svc_#{company_id}_#{random_token(10)}"
  end

  defp generate_secret do
    "sk_live_" <> random_token(32)
  end

  defp random_token(bytes) do
    :crypto.strong_rand_bytes(bytes)
    |> Base.url_encode64(padding: false)
  end
end
