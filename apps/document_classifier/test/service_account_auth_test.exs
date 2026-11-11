defmodule DocumentClassifier.TestIdentity do
  def authenticate(account, secret) when secret in ["secret", "sk_live_987654321"] do
    scopes =
      if account == "svc_read_only",
        do: ["ocr:read"],
        else: Process.get(:identity_scopes, ["classifier:write", "classifier:read"])

    {:ok,
     %{account_id: account, company_id: "44444444-4444-4444-8444-444444444444", scopes: scopes}}
  end

  def authenticate(_, _), do: {:error, :unauthorized}
end

defmodule DocumentClassifier.ServiceAccountAuthTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  setup do
    company = %{id: "44444444-4444-4444-8444-444444444444"}
    adapter = Application.get_env(:aike_auth, :adapter)
    Application.put_env(:aike_auth, :adapter, DocumentClassifier.TestIdentity)
    old = Application.get_env(:document_classifier, :service_account_auth_required, false)
    Application.put_env(:document_classifier, :service_account_auth_required, true)

    on_exit(fn ->
      if adapter,
        do: Application.put_env(:aike_auth, :adapter, adapter),
        else: Application.delete_env(:aike_auth, :adapter)

      Application.put_env(:document_classifier, :service_account_auth_required, old)
    end)

    {:ok, company: company}
  end

  test "classifier scopes distinguish write from read" do
    request = fn method, token ->
      conn(
        method,
        "/v1/classifications",
        Jason.encode!(%{"image" => Base.encode64("fake:cnh_front")})
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", token)
      |> DocumentClassifierWeb.Endpoint.call([])
    end

    assert request.(:post, "").status == 401
    assert request.(:post, "ApiKey svc_classifier:secret").status == 200
    assert request.(:post, "ApiKey svc_classifier:wrong").status == 401

    Process.put(:identity_scopes, ["ocr:write"])
    assert request.(:post, "ApiKey svc_classifier:secret").status == 403
  end
end
