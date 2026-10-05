defmodule DocumentOcr.ProvisioningApiTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  alias DocumentOcr.Repo
  alias KycCore.Auth.{Secret, ServiceAccount}
  alias KycCore.Tenants.Company

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "creates a company with a generated UUID" do
    conn =
      conn(:post, "/v1/companies", Jason.encode!(%{"name" => "Acme"}))
      |> put_req_header("content-type", "application/json")
      |> DocumentOcrWeb.Endpoint.call([])

    assert conn.status == 201
    body = Jason.decode!(conn.resp_body)
    assert body["name"] == "Acme"
    assert {:ok, _uuid} = Ecto.UUID.cast(body["id"])
    assert Repo.get!(Company, body["id"]).name == "Acme"
  end

  test "creates a service account and returns its secret once" do
    company = Repo.insert!(%Company{name: "Acme"})

    body = %{
      "company_id" => company.id,
      "name" => "Acme development",
      "scopes" => ["ocr:write", "ocr:read"]
    }

    conn =
      conn(:post, "/v1/service-accounts", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> DocumentOcrWeb.Endpoint.call([])

    assert conn.status == 201
    response = Jason.decode!(conn.resp_body)
    assert response["companyId"] == company.id
    assert is_binary(response["secret"])
    assert response["secret"] =~ "sk_live_"

    account = Repo.get_by!(ServiceAccount, account_id: response["accountId"])
    assert Secret.valid?(response["secret"], account.secret_hash)
    refute Map.has_key?(response, "secretHash")
  end

  test "rejects service account creation for an unknown company" do
    conn =
      conn(
        :post,
        "/v1/service-accounts",
        Jason.encode!(%{
          "company_id" => Ecto.UUID.generate(),
          "name" => "Unknown",
          "scopes" => ["ocr:read"]
        })
      )
      |> put_req_header("content-type", "application/json")
      |> DocumentOcrWeb.Endpoint.call([])

    assert conn.status == 404
  end
end
