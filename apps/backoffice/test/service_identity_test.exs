defmodule Backoffice.ServiceIdentityTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test
  alias Backoffice.{Repo, Provisioning, Auth.ServiceAccount, Tenants.Company}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    old = Application.get_env(:backoffice, :introspection_token)
    Application.put_env(:backoffice, :introspection_token, "internal-secret")

    on_exit(fn ->
      if old,
        do: Application.put_env(:backoffice, :introspection_token, old),
        else: Application.delete_env(:backoffice, :introspection_token)
    end)

    {:ok, company} = Provisioning.create_company(Repo, %{name: "Konoha"})

    {:ok, {account, secret}} =
      Provisioning.create_service_account(Repo, company, %{
        name: "API",
        scopes: ["classifier:write"]
      })

    %{company: company, account: account, secret: secret}
  end

  defp request(body, token \\ "internal-secret") do
    conn(:post, "/internal/v1/service-accounts/introspect", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
    |> BackofficeWeb.Endpoint.call([])
  end

  test "introspection is private and emits no credential material", %{
    account: account,
    secret: secret
  } do
    assert request("malformed-json", "wrong").status == 401
    assert request("malformed-json").status == 400
    response = request(Jason.encode!(%{accountId: account.account_id, secret: secret}))
    assert response.status == 200

    assert Jason.decode!(response.resp_body) == %{
             "accountId" => account.account_id,
             "companyId" => account.company_id,
             "scopes" => account.scopes
           }

    assert get_resp_header(response, "cache-control") == ["no-store"]
    refute response.resp_body =~ secret
    refute response.resp_body =~ account.secret_hash
  end

  test "revocation and company deactivation take effect without a cache", %{
    account: account,
    secret: secret,
    company: company
  } do
    body = Jason.encode!(%{accountId: account.account_id, secret: secret})
    assert request(body).status == 200
    Repo.update_all(ServiceAccount, set: [active: false])
    assert request(body).status == 401
    Repo.update_all(ServiceAccount, set: [active: true])
    Repo.update!(Ecto.Changeset.change(company, active: false))
    assert request(body).status == 401
    Repo.update_all(Company, set: [active: true])
    assert request(body).status == 200

    assert request(Jason.encode!(%{accountId: account.account_id, secret: "wrong"})).status ==
             401
  end
end
