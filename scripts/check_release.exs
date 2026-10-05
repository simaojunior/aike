# Run through a release's `eval`, from the repository root. Uses synthetic requests.
{app, excluded, endpoint, method, path, body, status} =
  case System.fetch_env!("RELEASE_NAME") do
    "document_classifier" ->
      {:document_classifier, [:document_ocr, :ecto, :ecto_sql, :oban],
       DocumentClassifierWeb.Endpoint, :post, "/v1/classifications",
       ~s({"source":{"type":"object_storage","key":"fake/cnh-front.jpg"}}), 200}

    "document_ocr" ->
      {:document_ocr, [:document_classifier], DocumentOcrWeb.Endpoint, :get,
       "/v1/documents/not-a-uuid", nil, 404}

    "biometrics" ->
      {:biometrics, [:document_ocr, :document_classifier], BiometricsWeb.Endpoint, :get,
       "/v1/facematch/not-a-uuid", nil, 404}
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
    "Bearer " <> Application.fetch_env!(app, :service_token)
  )

^status = endpoint.call(authorized, []).status

if app == :document_ocr do
  %{rows: [[1]]} = apply(Ecto.Adapters.SQL, :query!, [DocumentOcr.Repo, "SELECT 1", []])
end

IO.puts("#{app}: isolated production release and authentication verified")
