defmodule Backoffice.ProvisioningApiTest do
  alias Ecto.Adapters.SQL
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  alias Backoffice.Auth.{Secret, ServiceAccount}
  alias Backoffice.Repo
  alias Backoffice.Tenants.Company

  setup do
    :ok = SQL.Sandbox.checkout(Repo)
    SQL.Sandbox.mode(Repo, {:shared, self()})
    original = Application.fetch_env(:backoffice, :admin_token)
    Application.put_env(:backoffice, :admin_token, "backoffice-test-token")

    on_exit(fn ->
      case original do
        {:ok, token} -> Application.put_env(:backoffice, :admin_token, token)
        :error -> Application.delete_env(:backoffice, :admin_token)
      end
    end)

    {:ok, _} =
      Backoffice.Accounts.bootstrap(%{
        company_name: "Owner",
        name: "Admin",
        email: "admin@example.test",
        password: "Correct horse battery staple 42!"
      })

    {:ok, pair} =
      Backoffice.Sessions.login("admin@example.test", "Correct horse battery staple 42!")

    %{token: pair.access_token}
  end

  test "creates a company with a generated UUID", %{token: token} do
    conn =
      conn(:post, "/v1/companies", Jason.encode!(%{"name" => "Konoha"}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer " <> token)
      |> BackofficeWeb.Endpoint.call([])

    assert conn.status == 201
    body = Jason.decode!(conn.resp_body)
    assert body["name"] == "Konoha"
    assert {:ok, _uuid} = Ecto.UUID.cast(body["id"])
    assert Repo.get!(Company, body["id"]).name == "Konoha"
  end

  test "administrative authentication precedes parsing and denies service credentials" do
    for authorization <- [nil, "Bearer wrong", "ApiKey svc_customer:secret"] do
      request =
        conn(:post, "/v1/companies", "{")
        |> put_req_header("content-type", "application/json")

      request =
        if authorization,
          do: put_req_header(request, "authorization", authorization),
          else: request

      response = BackofficeWeb.Endpoint.call(request, [])
      assert response.status == 401
      assert %{"code" => "unauthorized"} = Jason.decode!(response.resp_body)
    end

    assert Repo.aggregate(Company, :count) == 1
  end

  test "missing or empty admin configuration fails closed" do
    for token <- [nil, ""] do
      Application.put_env(:backoffice, :admin_token, token)

      response =
        conn(:post, "/v1/companies", ~s({"name":"Konoha"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer ")
        |> BackofficeWeb.Endpoint.call([])

      assert response.status == 401
    end
  end

  test "authenticated malformed JSON has a sanitized error", %{token: token} do
    response =
      conn(:post, "/v1/companies", "{")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer " <> token)
      |> BackofficeWeb.Endpoint.call([])

    assert response.status == 400
    assert Jason.decode!(response.resp_body)["code"] == "invalid_json"
  end

  test "creates a service account and returns its secret once", %{token: token} do
    company = Repo.insert!(%Company{name: "Konoha"})

    body = %{
      "company_id" => company.id,
      "name" => "Konoha development",
      "scopes" => ["ocr:write", "ocr:read"]
    }

    conn =
      conn(:post, "/v1/service-accounts", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer " <> token)
      |> BackofficeWeb.Endpoint.call([])

    assert conn.status == 201
    response = Jason.decode!(conn.resp_body)
    assert response["companyId"] == company.id
    assert is_binary(response["secret"])
    assert response["secret"] =~ "sk_live_"

    account = Repo.get_by!(ServiceAccount, account_id: response["accountId"])
    assert Secret.valid?(response["secret"], account.secret_hash)
    refute Map.has_key?(response, "secretHash")
  end

  test "rejects service account creation for an unknown company", %{token: token} do
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
      |> put_req_header("authorization", "Bearer " <> token)
      |> BackofficeWeb.Endpoint.call([])

    assert conn.status == 404
  end
end
