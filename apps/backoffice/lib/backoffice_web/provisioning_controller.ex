defmodule BackofficeWeb.ProvisioningController do
  @moduledoc "Administrative provisioning through scope-checked contexts."
  use BackofficeWeb, :controller
  action_fallback(BackofficeWeb.FallbackController)
  alias BackofficeWeb.Schemas.Params

  plug(BackofficeWeb.ValidateParams,
    create_company: &Params.create_company/1,
    create_service_account: &Params.create_service_account/1
  )

  alias Backoffice.Administration
  alias BackofficeWeb.ProvisioningJSON
  alias KycCore.JsonKeyFormatter

  def create_company(conn, %{"name" => name}) when is_binary(name) do
    with {:ok, company} <-
           Administration.create_company(conn.assigns.identity.user, %{name: name}),
         do:
           conn
           |> put_resp_header("location", "/v1/companies/#{company.id}")
           |> put_status(:created)
           |> json(JsonKeyFormatter.format(ProvisioningJSON.company(company)))
  end

  def create_company(_conn, _), do: {:error, :invalid_request}

  def create_service_account(conn, %{"name" => name, "scopes" => scopes} = params)
      when is_binary(name) and is_list(scopes) do
    attrs = %{
      company_id: params["company_id"] || params["companyId"],
      name: name,
      scopes: scopes,
      account_id: params["account_id"] || params["accountId"]
    }

    with {:ok, {account, secret}} <-
           Administration.create_service_account(conn.assigns.identity.user, attrs),
         do:
           conn
           |> put_resp_header("location", "/v1/service-accounts/#{account.id}")
           |> put_status(:created)
           |> json(JsonKeyFormatter.format(ProvisioningJSON.service_account(account, secret)))
  end

  def create_service_account(_conn, _), do: {:error, :invalid_request}
end
