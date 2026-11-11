# Run through a release's `eval`, from the repository root. Uses synthetic requests.
{app, excluded, endpoint, method, path, body, status} =
  case System.fetch_env!("RELEASE_NAME") do
    "document_classifier" ->
      {:document_classifier, [:document_ocr, :backoffice, :biometrics, :ecto_sql, :oban],
       DocumentClassifierWeb.Endpoint, :post, "/v1/classifications",
       Jason.encode!(%{"image" => Base.encode64("fake:cnh_front")}), 200}

    "document_ocr" ->
      {:document_ocr, [:document_classifier], DocumentOcrWeb.Endpoint, :get,
       "/v1/extractions/00000000-0000-0000-0000-000000000000", nil, 404}

    "biometrics" ->
      {:biometrics, [:document_ocr, :document_classifier], BiometricsWeb.Endpoint, :get,
       "/v1/facematch/00000000-0000-0000-0000-000000000000", nil, 404}
  end

{:ok, _} = Application.ensure_all_started(app)
true = Application.fetch_env!(app, :auth_required)
started = Enum.map(Application.started_applications(), &elem(&1, 0))

if Enum.any?(excluded, &(&1 in started or Application.spec(&1) != nil)) do
  raise "Release contains or starts another service's infrastructure"
end

conn =
  Plug.Test.conn(method, path, body)
  |> Plug.Conn.put_req_header("content-type", "application/json")

401 = endpoint.call(conn, []).status

authorized =
  Plug.Conn.put_req_header(
    conn,
    "authorization",
    "ApiKey " <>
      System.fetch_env!("AIKE_ACCOUNT_ID") <> ":" <> System.fetch_env!("AIKE_ACCOUNT_SECRET")
  )

# Release verification uses synthetic bytes; production engine configuration is unchanged.
if app == :document_classifier do
  Application.put_env(app, :engine, DocumentClassifier.Engine.Fake)
end

^status = endpoint.call(authorized, []).status

if app == :document_ocr do
  %{rows: [[1]]} = apply(Ecto.Adapters.SQL, :query!, [DocumentOcr.Repo, "SELECT 1", []])
end

IO.puts("#{app}: isolated production release and authentication verified")
