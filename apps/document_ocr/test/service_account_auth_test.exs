defmodule DocumentOcr.ServiceAccountAuthTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias DocumentOcr.{Repo, Documents}
  alias KycCore.Auth.{Secret, ServiceAccount}
  alias KycCore.Tenants.Company

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    company = Repo.insert!(%Company{name: "Acme"})
    old_required = Application.get_env(:document_ocr, :service_account_auth_required, false)
    Application.put_env(:document_ocr, :service_account_auth_required, true)

    on_exit(fn ->
      Application.put_env(:document_ocr, :service_account_auth_required, old_required)
    end)

    {:ok, company: company}
  end

  test "valid ApiKey derives company and service account from the database", %{company: company} do
    {:ok, account} =
      Repo.insert(%ServiceAccount{
        account_id: "svc_acme_prod_123",
        secret_hash: Secret.hash("sk_live_987654321"),
        scopes: ["ocr:write", "ocr:read"],
        company_id: company.id,
        name: "Acme Main Backend"
      })

    body = %{
      "external_id" => "user-9876",
      "document_type" => "cnh",
      "country" => "BR",
      "images" => [
        %{"side" => "front", "source" => %{"type" => "object_storage", "key" => "front.jpg"}}
      ],
      "app_id" => "attacker-company"
    }

    conn =
      conn(:post, "/v1/documents", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "ApiKey svc_acme_prod_123:sk_live_987654321")
      |> DocumentOcrWeb.Endpoint.call([])

    assert conn.status == 202
    id = Jason.decode!(conn.resp_body)["id"]
    assert Documents.get_document!(id).app_id == account.company_id
  end

  test "invalid secret is unauthorized and missing scope is forbidden", %{company: company} do
    Repo.insert!(%ServiceAccount{
      account_id: "svc_read_only",
      secret_hash: Secret.hash("secret"),
      scopes: ["ocr:read"],
      company_id: company.id,
      name: "Read only"
    })

    request = fn token ->
      conn(:post, "/v1/documents", Jason.encode!(%{"app_id" => "ignored"}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", token)
      |> DocumentOcrWeb.Endpoint.call([])
    end

    assert request.("ApiKey svc_read_only:wrong").status == 401
    assert request.("ApiKey svc_read_only:secret").status == 403
  end
end
