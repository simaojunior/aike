defmodule BackofficeWeb.ProvisioningJSON do
  @moduledoc "JSON views for authenticated administrative provisioning."

  @spec company(map()) :: map()
  def company(company), do: %{id: company.id, name: company.name, active: company.active}

  @spec service_account(map(), String.t()) :: map()
  def service_account(account, secret) do
    %{
      account_id: account.account_id,
      company_id: account.company_id,
      name: account.name,
      scopes: account.scopes,
      active: account.active,
      secret: secret
    }
  end
end
