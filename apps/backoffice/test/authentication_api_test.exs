defmodule Backoffice.AuthenticationApiTest do
  alias Backoffice.Accounts.Password
  alias Ecto.Adapters.SQL
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test
  alias Backoffice.{Accounts, Repo, Sessions}
  @password "Correct horse battery staple 42!"
  @bootstrap String.duplicate("b", 32)

  setup do
    :ok = SQL.Sandbox.checkout(Repo)
    SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Application.get_env(:backoffice, :bootstrap_token)
    Application.put_env(:backoffice, :bootstrap_token, @bootstrap)
    on_exit(fn -> Application.put_env(:backoffice, :bootstrap_token, previous) end)
    :ok
  end

  test "bootstrap credential only bootstraps once and never authorizes normal APIs" do
    body = %{
      companyName: "Owner",
      name: "Admin",
      email: "admin@example.test",
      password: @password
    }

    assert request(:post, "/v1/auth/bootstrap", body, "wrong").status == 401
    response = request(:post, "/v1/auth/bootstrap", body, @bootstrap)
    assert response.status == 201
    refute Map.has_key?(Jason.decode!(response.resp_body), "passwordHash")
    refute Map.has_key?(Jason.decode!(response.resp_body), "password")
    assert request(:post, "/v1/auth/bootstrap", body, @bootstrap).status == 409
    assert request(:post, "/v1/companies", %{name: "Denied"}, @bootstrap).status == 401
    response = request(:post, "/v1/auth/login", %{email: body.email, password: @password})
    assert response.status == 200
    assert get_resp_header(response, "cache-control") == ["no-store"]
    %{"accessToken" => access, "refreshToken" => refresh} = Jason.decode!(response.resp_body)
    assert request(:get, "/v1/auth/me", %{}, access).status == 200
    assert request(:get, "/v1/auth/me", %{}, refresh).status == 401
    assert request(:post, "/v1/auth/logout", %{}, access).status == 200
    assert request(:get, "/v1/auth/me", %{}, access).status == 401
  end

  test "tenant administration enforces company scope and rejects mass assignment" do
    {:ok, owner} =
      Accounts.bootstrap(%{
        company_name: "Owner",
        name: "Admin",
        email: "admin@example.test",
        password: @password
      })

    {:ok, company} = Backoffice.Provisioning.create_company(Repo, %{name: "Tenant"})

    {:ok, admin} =
      Accounts.create_user(owner, %{
        company_id: company.id,
        name: "Admin",
        email: "tenant@example.test",
        password: @password,
        role: :company_admin
      })

    {:ok, pair} = Sessions.login(admin.email, @password)
    assert request(:post, "/v1/companies", %{name: "Denied"}, pair.access_token).status == 403

    assert request(
             :post,
             "/v1/service-accounts",
             %{companyId: owner.company_id, name: "Denied", scopes: ["ocr:read"]},
             pair.access_token
           ).status == 403

    response =
      request(
        :post,
        "/v1/users",
        %{
          name: "Member",
          email: "member@example.test",
          password: @password,
          isPlatform: true,
          scopes: ["companies.create"]
        },
        pair.access_token
      )

    assert response.status == 201
    member = Jason.decode!(response.resp_body)
    assert member["role"] == "company_user"
    assert member["companyId"] == company.id
    refute "companies.create" in member["scopes"]

    assert request(
             :patch,
             "/v1/users/" <> member["id"],
             %{role: "platform_admin"},
             pair.access_token
           ).status == 403
  end

  test "missing and existing identities are throttled with identical errors" do
    for _ <- 1..10 do
      response =
        request(:post, "/v1/auth/login", %{email: "missing@example.test", password: @password})

      assert response.status == 401

      assert %{"code" => "invalid_credentials", "detail" => "Email or password is invalid."} =
               Jason.decode!(response.resp_body)
    end

    assert request(:post, "/v1/auth/login", %{email: "missing@example.test", password: @password}).status ==
             429
  end

  test "unknown domain errors cannot silently alter the contract" do
    assert_raise KeyError, fn -> BackofficeWeb.ResponseHelpers.error_info(:unregistered) end
  end

  test "bootstrap identifies a short password without echoing credentials or leaving a company" do
    body = %{
      companyName: "Owner",
      name: "Admin",
      email: "admin@example.test",
      password: "short-secret"
    }

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        response = request(:post, "/v1/auth/bootstrap", body, @bootstrap)
        assert response.status == 422
        assert get_resp_header(response, "cache-control") == ["no-store"]
        payload = Jason.decode!(response.resp_body)
        assert payload["code"] == "validation"
        assert [request_id] = get_resp_header(response, "x-request-id")
        assert is_binary(request_id)
        refute Map.has_key?(payload, "requestId")

        assert payload["errors"] == [
                 %{
                   "field" => "password",
                   "detail" => "Must contain at least 15 characters."
                 }
               ]

        refute response.resp_body =~ body.password
        refute response.resp_body =~ body.email
      end)

    refute log =~ body.password
    refute log =~ body.email
    assert Repo.aggregate(Backoffice.Tenants.Company, :count) == 0
    assert Repo.aggregate(Backoffice.Accounts.User, :count) == 0
  end

  test "bootstrap identifies companyName rather than the administrator name" do
    response =
      request(
        :post,
        "/v1/auth/bootstrap",
        %{companyName: "X", name: "Admin", email: "admin@example.test", password: @password},
        @bootstrap
      )

    assert response.status == 422

    assert [%{"field" => "companyName", "detail" => "Must contain at least 2 characters."}] =
             Jason.decode!(response.resp_body)["errors"]
  end

  test "bootstrap reports missing and invalid fields with stable public codes" do
    response =
      request(
        :post,
        "/v1/auth/bootstrap",
        %{companyName: "Owner", name: "A", email: "bad-email", password: 123},
        @bootstrap
      )

    assert response.status == 422
    details = Jason.decode!(response.resp_body)["errors"]

    assert Enum.any?(
             details,
             &(&1["field"] == "email" and &1["detail"] == "This field has an invalid format.")
           )

    assert Enum.any?(
             details,
             &(&1["field"] == "name" and &1["detail"] == "Must contain at least 2 characters.")
           )

    assert Enum.any?(
             details,
             &(&1["field"] == "password" and &1["detail"] == "This field has an invalid type.")
           )

    response = request(:post, "/v1/auth/bootstrap", %{companyName: "Owner"}, @bootstrap)
    assert response.status == 422

    assert Enum.map(Jason.decode!(response.resp_body)["errors"], & &1["field"]) == [
             "email",
             "name",
             "password"
           ]

    assert request(:post, "/v1/auth/bootstrap", %{}, "wrong").status == 401
  end

  test "password limits use characters for minimum and bytes for maximum" do
    assert Password.valid?(String.duplicate("é", 15))
    refute Password.valid?(String.duplicate("é", 14))
    assert Password.valid?(String.duplicate("a", 1024))
    refute Password.valid?(String.duplicate("a", 1025))
  end

  test "Peri rejects input before the bootstrap context executes any SQL" do
    handler = "bootstrap-input-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler,
        [:backoffice, :repo, :query],
        fn _, _, _, _ -> send(parent, :sql_query) end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    params = %{
      "companyName" => "Owner",
      "name" => "Admin",
      "email" => "admin@example.test",
      "password" => "short"
    }

    connection =
      conn(:post, "/v1/auth/bootstrap")
      |> put_req_header("authorization", "Bearer " <> @bootstrap)

    connection = %{connection | params: params}
    response = BackofficeWeb.AuthController.call(connection, :bootstrap)
    assert response.status == 422

    assert %{"code" => "validation", "errors" => [%{"field" => "password"}]} =
             Jason.decode!(response.resp_body)

    refute_received :sql_query
  end

  test "created responses include the resource location" do
    response =
      request(
        :post,
        "/v1/auth/bootstrap",
        %{companyName: "Owner", name: "Admin", email: "admin@example.test", password: @password},
        @bootstrap
      )

    assert response.status == 201
    id = Jason.decode!(response.resp_body)["id"]
    assert get_resp_header(response, "location") == ["/v1/users/" <> id]
  end

  defp request(method, path, body, token \\ "") do
    conn(method, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
    |> BackofficeWeb.Endpoint.call([])
  end
end
