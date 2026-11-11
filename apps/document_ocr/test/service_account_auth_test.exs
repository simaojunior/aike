defmodule DocumentOcr.TestIdentity do
  def authenticate(account, "secret") do
    scopes = if account == "read_only", do: ["ocr:read"], else: ["ocr:write", "ocr:read"]

    {:ok,
     %{account_id: account, company_id: "44444444-4444-4444-8444-444444444444", scopes: scopes}}
  end

  def authenticate(_, _), do: {:error, :unauthorized}
end

defmodule DocumentOcr.ServiceAccountAuthTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn
  alias DocumentOcr.{Documents, Repo}
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    adapter = Application.get_env(:aike_auth, :adapter)
    required = Application.get_env(:document_ocr, :service_account_auth_required, false)
    Application.put_env(:aike_auth, :adapter, DocumentOcr.TestIdentity)
    Application.put_env(:document_ocr, :service_account_auth_required, true)

    on_exit(fn ->
      if adapter,
        do: Application.put_env(:aike_auth, :adapter, adapter),
        else: Application.delete_env(:aike_auth, :adapter)

      Application.put_env(:document_ocr, :service_account_auth_required, required)
    end)
  end

  defp request(body, credentials) do
    conn(:post, "/v1/extractions", Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", credentials)
    |> DocumentOcrWeb.Endpoint.call([])
  end

  test "identity boundary determines tenant, ignoring a tenant supplied in the body" do
    response =
      request(
        %{
          "externalId" => "user-9876",
          "documentType" => "cnh",
          "country" => "BR",
          "images" => [%{"side" => "front", "image" => Base.encode64("front.jpg")}],
          "appId" => "attacker-company"
        },
        "ApiKey writer:secret"
      )

    assert response.status == 202
    id = Jason.decode!(response.resp_body)["id"]
    assert Documents.get_document!(id).app_id == "44444444-4444-4444-8444-444444444444"
  end

  test "invalid credentials and insufficient scopes fail closed" do
    assert request(%{}, "ApiKey read_only:wrong").status == 401
    assert request(%{}, "ApiKey read_only:secret").status == 403
  end
end
