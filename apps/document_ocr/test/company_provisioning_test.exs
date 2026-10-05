defmodule Aike.CompanyProvisioningTest do
  use ExUnit.Case, async: false

  alias DocumentOcr.Repo
  alias KycCore.Auth.{Provisioning, Secret}
  alias KycCore.Tenants.Company

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "creates a company and a service account with a one-time secret" do
    assert {:ok, %Company{} = company} =
             Provisioning.create_company(Repo, %{name: "Acme"})

    assert {:ok, {account, secret}} =
             Provisioning.create_service_account(Repo, company, %{
               name: "Acme development",
               account_id: "svc_acme_dev",
               scopes: ["ocr:write", "ocr:read"]
             })

    assert account.company_id == company.id
    assert account.account_id == "svc_acme_dev"
    assert account.secret_hash != secret
    assert Secret.valid?(secret, account.secret_hash)
    refute Map.has_key?(Map.from_struct(account), :secret)
  end

  test "rejects an account for an unknown company" do
    assert {:error, :company_not_found} =
             Provisioning.create_service_account(Repo, Ecto.UUID.generate(), %{
               name: "Unknown",
               scopes: ["ocr:read"]
             })
  end

  test "rejects scopes outside the service account dictionary" do
    assert {:ok, company} =
             Provisioning.create_company(Repo, %{name: "Acme"})

    assert {:error, changeset} =
             Provisioning.create_service_account(Repo, company, %{
               name: "Invalid",
               scopes: ["ocr:delete"]
             })

    assert %{scopes: _} = errors_on(changeset)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
