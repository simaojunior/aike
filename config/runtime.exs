import Config

# Mix starts the umbrella by default; named releases configure only their service.
services =
  case System.get_env("RELEASE_NAME") do
    nil -> [:document_ocr, :document_classifier, :biometrics, :backoffice]
    "document_ocr" -> [:document_ocr]
    "document_classifier" -> [:document_classifier]
    "biometrics" -> [:biometrics]
    "backoffice" -> [:backoffice]
    _ -> raise ArgumentError, "Unknown Aike release name"
  end

required_env = fn primary, fallback ->
  value = System.get_env(primary) || (fallback && System.get_env(fallback))

  if is_binary(value) and String.trim(value) != "" do
    value
  else
    raise ArgumentError, "Missing non-empty environment variable #{primary}"
  end
end

http_ip =
  case System.get_env("AIKE_HTTP_IP", "127.0.0.1")
       |> String.to_charlist()
       |> :inet.parse_address() do
    {:ok, address} -> address
    {:error, _} -> raise ArgumentError, "AIKE_HTTP_IP must be an IPv4 or IPv6 address"
  end

positive_env = fn name ->
  case System.get_env(name) do
    nil ->
      nil

    value ->
      case Integer.parse(value) do
        {number, ""} when number > 0 -> number
        _ -> raise ArgumentError, "#{name} must be a positive integer"
      end
  end
end

for {key, name} <- [
      ocr_processes: "AIKE_OCR_PROCESSES",
      max_documents: "AIKE_MAX_DOCUMENTS",
      max_waiting_documents: "AIKE_MAX_WAITING_DOCUMENTS",
      admission_wait_ms: "AIKE_ADMISSION_WAIT_MS",
      retry_after_seconds: "AIKE_RETRY_AFTER_SECONDS"
    ],
    value = positive_env.(name) do
  config :aike_vision, [{key, value}]
end

if models = System.get_env("AIKE_FACE_MODELS_DIR") do
  config :aike_vision, face_models_dir: Path.expand(models)
end

if config_env() != :test and :document_ocr in services do
  ocr_jobs = positive_env.("OCR_QUEUE_CONCURRENCY") || max(1, div(System.schedulers_online(), 2))

  config :document_ocr, Oban,
    queues: [preprocess: 2, ocr: ocr_jobs, default: 2, maintenance: 1, webhooks: 5]
end

if :backoffice in services do
  config :backoffice, BackofficeWeb.Endpoint,
    http: [ip: http_ip, port: String.to_integer(System.get_env("BACKOFFICE_PORT", "4003"))]

  if System.get_env("PHX_SERVER") == "true" do
    config :backoffice, BackofficeWeb.Endpoint, server: true
  end

  if token =
       System.get_env("BACKOFFICE_BOOTSTRAP_TOKEN") || System.get_env("BACKOFFICE_ADMIN_TOKEN") do
    config :backoffice, :bootstrap_token, token
  end

  if database_url = System.get_env("BACKOFFICE_DATABASE_URL") do
    config :backoffice, Backoffice.Repo, url: database_url
  end

  if config_env() == :prod do
    config :backoffice, Backoffice.Repo, url: required_env.("BACKOFFICE_DATABASE_URL", nil)

    config :backoffice, BackofficeWeb.Endpoint,
      secret_key_base: required_env.("BACKOFFICE_SECRET_KEY_BASE", nil)
  end
end

if :biometrics in services do
  config :biometrics, BiometricsWeb.Endpoint,
    http: [ip: http_ip, port: String.to_integer(System.get_env("BIOMETRICS_PORT", "4002"))]

  if System.get_env("PHX_SERVER") == "true" do
    config :biometrics, BiometricsWeb.Endpoint, server: true
  end

  if database_url = System.get_env("BIOMETRICS_DATABASE_URL") do
    config :biometrics, Biometrics.Repo, url: database_url
  end

  if config_env() == :prod do
    config :biometrics, :service_token, required_env.("BIOMETRICS_SERVICE_TOKEN", "SERVICE_TOKEN")
    config :biometrics, :auth_required, true
    config :biometrics, :service_account_auth_required, true
    config :biometrics, Biometrics.Repo, url: required_env.("BIOMETRICS_DATABASE_URL", nil)

    config :biometrics, BiometricsWeb.Endpoint,
      secret_key_base: required_env.("BIOMETRICS_SECRET_KEY_BASE", "SECRET_KEY_BASE")
  end
end

if :document_classifier in services do
  config :document_classifier, DocumentClassifierWeb.Endpoint,
    http: [ip: http_ip, port: String.to_integer(System.get_env("CLASSIFIER_PORT", "4001"))]

  if System.get_env("PHX_SERVER") == "true" do
    config :document_classifier, DocumentClassifierWeb.Endpoint, server: true
  end

  if config_env() == :prod do
    config :document_classifier,
           :service_token,
           required_env.("CLASSIFIER_SERVICE_TOKEN", "SERVICE_TOKEN")

    config :document_classifier, :service_account_auth_required, true

    config :document_classifier, DocumentClassifierWeb.Endpoint,
      secret_key_base: required_env.("CLASSIFIER_SECRET_KEY_BASE", "SECRET_KEY_BASE")
  end
end

if :document_ocr in services do
  config :document_ocr, DocumentOcrWeb.Endpoint,
    http: [ip: http_ip, port: String.to_integer(System.get_env("PORT", "4000"))]

  if System.get_env("PHX_SERVER") == "true" do
    config :document_ocr, DocumentOcrWeb.Endpoint, server: true
  end

  if config_env() == :prod do
    config :document_ocr, :service_token, required_env.("SERVICE_TOKEN", nil)
    config :document_ocr, :service_account_auth_required, true
    config :document_ocr, DocumentOcr.Repo, url: required_env.("DATABASE_URL", nil)

    signing_key = required_env.("WEBHOOK_SIGNING_KEY", nil)

    if byte_size(signing_key) < 32 do
      raise ArgumentError, "WEBHOOK_SIGNING_KEY must have at least 32 bytes"
    end

    config :document_ocr,
      webhook_signing_key: signing_key,
      webhook_require_https: true,
      webhook_allow_private_targets: false

    config :document_ocr, DocumentOcrWeb.Endpoint,
      secret_key_base: required_env.("SECRET_KEY_BASE", nil)
  end
end

case System.get_env("AIKE_STORAGE_ADAPTER") do
  nil -> :ok
  "s3" -> config :aike_storage, adapter: AikeStorage.Adapter.S3
  "local" -> config :aike_storage, adapter: AikeStorage.Adapter.Local
  other -> raise ArgumentError, "AIKE_STORAGE_ADAPTER must be s3 or local, got: #{inspect(other)}"
end

if upload_dir = System.get_env("AIKE_UPLOAD_DIR") do
  if String.trim(upload_dir) == "" do
    raise ArgumentError, "AIKE_UPLOAD_DIR must not be empty"
  end

  config :aike_storage, local_root: Path.expand(upload_dir)
end

for service <- services, service in [:document_ocr, :biometrics] do
  prefix = if service == :document_ocr, do: "OCR", else: "BIOMETRICS"

  if token = System.get_env(prefix <> "_METRICS_TOKEN") do
    if String.trim(token) == "" do
      raise ArgumentError, prefix <> "_METRICS_TOKEN must not be empty"
    end

    config service, metrics_token: token
  end
end

# Identity transport is shared by the processing services and the administrative issuer.
if :backoffice in services do
  if config_env() == :prod do
    config :backoffice, :introspection_token, required_env.("AIKE_AUTH_TOKEN", nil)
  else
    config :backoffice, :introspection_token, System.get_env("AIKE_AUTH_TOKEN")
  end
end

if Enum.any?(services, &(&1 in [:document_ocr, :document_classifier, :biometrics])) do
  case System.get_env("AIKE_AUTH_CACHE_TTL_SECONDS") do
    nil ->
      :ok

    value ->
      case Integer.parse(value) do
        {seconds, ""} when seconds >= 0 and seconds <= 300 ->
          config :aike_auth, cache_ttl_seconds: seconds

        _ ->
          raise ArgumentError, "AIKE_AUTH_CACHE_TTL_SECONDS must be an integer from 0 to 300"
      end
  end

  case System.get_env("AIKE_AUTH_ALLOW_HTTP") do
    nil -> :ok
    "true" -> config :aike_auth, allow_http: true
    "false" -> config :aike_auth, allow_http: false
    _ -> raise ArgumentError, "AIKE_AUTH_ALLOW_HTTP must be true or false"
  end

  if config_env() == :prod do
    config :aike_auth,
      url: required_env.("BACKOFFICE_AUTH_URL", nil),
      token: required_env.("AIKE_AUTH_TOKEN", nil)
  else
    config :aike_auth,
      url:
        System.get_env(
          "BACKOFFICE_AUTH_URL",
          "http://localhost:4003/internal/v1/service-accounts/introspect"
        ),
      token: System.get_env("AIKE_AUTH_TOKEN")
  end
end

if config_env() == :prod and Enum.any?(services, &(&1 in [:document_ocr, :biometrics])) and
     System.get_env("AIKE_STORAGE_ADAPTER") != "local" do
  config :aike_storage,
    s3: [
      endpoint: required_env.("S3_ENDPOINT", nil),
      bucket: required_env.("S3_BUCKET", nil),
      region: System.get_env("S3_REGION", "auto"),
      access_key_id: required_env.("S3_ACCESS_KEY_ID", nil),
      secret_access_key: required_env.("S3_SECRET_ACCESS_KEY", nil)
    ]
end
