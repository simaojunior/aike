defmodule DocumentClassifier.ServiceAccountAuthTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias DocumentClassifier.Repo
  alias KycCore.Auth.{Secret, ServiceAccount}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    old = Application.get_env(:document_classifier, :service_account_auth_required, false)
    Application.put_env(:document_classifier, :service_account_auth_required, true)

    on_exit(fn ->
      Application.put_env(:document_classifier, :service_account_auth_required, old)
    end)

    :ok
  end

  test "classifier scopes distinguish write from read" do
    Repo.insert!(%ServiceAccount{
      account_id: "svc_classifier",
      secret_hash: Secret.hash("secret"),
      scopes: ["ocr:write"],
      company_id: "acme",
      name: "Classifier integration"
    })

    request = fn method, token ->
      conn(
        method,
        "/v1/classifications",
        Jason.encode!(%{"source" => %{"type" => "object_storage", "key" => "x"}})
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", token)
      |> DocumentClassifierWeb.Endpoint.call([])
    end

    assert request.(:post, "ApiKey svc_classifier:secret").status == 200
    assert request.(:post, "ApiKey svc_classifier:wrong").status == 401
  end
end
