defmodule DocumentOcrWeb.ProvisioningController do
  @moduledoc "Temporary local provisioning API for companies and service accounts."

  use DocumentOcrWeb, :controller

  alias DocumentOcr.Repo
  alias KycCore.Auth.Provisioning
  alias DocumentOcrWeb.ProvisioningJSON
  alias KycCore.JsonKeyFormatter

  @spec create_company(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_company(conn, %{"name" => name}) when is_binary(name) do
    case Provisioning.create_company(Repo, %{name: name}) do
      {:ok, company} ->
        conn
        |> put_status(:created)
        |> json(JsonKeyFormatter.format(ProvisioningJSON.company(company)))

      {:error, _changeset} ->
        invalid_request(conn)
    end
  end

  def create_company(conn, _params), do: invalid_request(conn)

  @spec create_service_account(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_service_account(conn, params) do
    attrs = %{
      company_id: params["company_id"] || params["companyId"],
      name: params["name"],
      scopes: params["scopes"],
      account_id: params["account_id"] || params["accountId"]
    }

    case valid_service_account_attrs?(attrs) do
      true -> provision_service_account(conn, attrs)
      false -> invalid_request(conn)
    end
  end

  defp provision_service_account(conn, attrs) do
    case Provisioning.create_service_account(Repo, attrs.company_id, attrs) do
      {:ok, {account, secret}} ->
        body = ProvisioningJSON.service_account(account, secret)
        conn |> put_status(:created) |> json(JsonKeyFormatter.format(body))

      {:error, :company_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "company_not_found"})

      {:error, _changeset} ->
        invalid_request(conn)
    end
  end

  defp valid_service_account_attrs?(%{company_id: company_id, name: name, scopes: scopes}) do
    is_binary(company_id) and is_binary(name) and is_list(scopes)
  end

  defp invalid_request(conn),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_request"})
end
