# Run using the backoffice release's eval. Synthetic writes are rolled back.
{:ok, _} = Application.ensure_all_started(:backoffice)

for app <- [:document_ocr, :document_classifier, :biometrics, :oban] do
  if Application.spec(app), do: raise("Backoffice release includes #{app}")
end

401 =
  Plug.Test.conn(:post, "/v1/companies", ~s({"name":"Release verification"}))
  |> Plug.Conn.put_req_header("content-type", "application/json")
  |> BackofficeWeb.Endpoint.call([])
  |> Map.fetch!(:status)

{:error, :verification_complete} =
  Backoffice.Repo.transaction(fn ->
    password = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    email = "release-verification@example.test"

    {:ok, _} =
      Backoffice.Accounts.bootstrap(%{
        company_name: "Release owner",
        name: "Release admin",
        email: email,
        password: password
      })

    {:ok, pair} = Backoffice.Sessions.login(email, password)

    request = fn path, body ->
      Plug.Test.conn(:post, path, Jason.encode!(body))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header(
        "authorization",
        "Bearer " <> pair.access_token
      )
      |> BackofficeWeb.Endpoint.call([])
    end

    company = request.("/v1/companies", %{name: "Release verification"})
    201 = company.status
    company_id = Jason.decode!(company.resp_body)["id"]

    account =
      request.("/v1/service-accounts", %{
        companyId: company_id,
        name: "Release verification",
        scopes: ["classifier:write"]
      })

    201 = account.status
    body = Jason.decode!(account.resp_body)
    saved = Backoffice.Repo.get_by!(Backoffice.Auth.ServiceAccount, account_id: body["accountId"])
    true = Backoffice.Auth.Secret.valid?(body["secret"], saved.secret_hash)
    Backoffice.Repo.rollback(:verification_complete)
  end)

IO.puts("Backoffice: isolated release, administrative auth and provisioning verified")
