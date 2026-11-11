defmodule Backoffice.Provisioning do
  @moduledoc "Creates tenant companies and one-time service credentials."

  alias Backoffice.Auth.{Secret, ServiceAccount}
  alias Backoffice.Tenants.Company

  @type repo :: module()
  @type provisioned_account :: {ServiceAccount.t(), String.t()}

  @spec create_company(repo(), map()) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def create_company(repo, attrs) do
    %Company{}
    |> Company.changeset(attrs)
    |> repo.insert()
  end

  @spec create_service_account(repo(), Company.t() | Ecto.UUID.t(), map()) ::
          {:ok, provisioned_account()} | {:error, :company_not_found | Ecto.Changeset.t()}
  def create_service_account(repo, company_or_id, attrs)

  def create_service_account(repo, %Company{} = company, attrs) do
    provision_active_company(repo, company, attrs)
  end

  def create_service_account(repo, company_id, attrs) when is_binary(company_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(company_id),
         %Company{} = company <- repo.get(Company, uuid) do
      provision_active_company(repo, company, attrs)
    else
      _ -> {:error, :company_not_found}
    end
  end

  def create_service_account(_repo, _company, _attrs), do: {:error, :company_not_found}

  defp provision_active_company(repo, %Company{active: true} = company, attrs),
    do: insert_service_account(repo, company, attrs)

  defp provision_active_company(_repo, _company, _attrs), do: {:error, :company_not_found}

  defp insert_service_account(repo, company, attrs) do
    secret = generate_secret()

    account_id =
      Map.get(attrs, :account_id) || Map.get(attrs, "account_id") ||
        generate_account_id()

    account_attrs =
      attrs
      |> Map.put(:account_id, account_id)
      |> Map.put(:company_id, company.id)
      |> Map.put(:secret_hash, Secret.hash(secret))

    with {:ok, account} <-
           %ServiceAccount{} |> ServiceAccount.changeset(account_attrs) |> repo.insert(),
         do: {:ok, {account, secret}}
  end

  defp generate_account_id, do: "svc_#{random_token(16)}"

  defp generate_secret do
    "sk_live_" <> random_token(32)
  end

  defp random_token(bytes) do
    :crypto.strong_rand_bytes(bytes)
    |> Base.url_encode64(padding: false)
  end
end
