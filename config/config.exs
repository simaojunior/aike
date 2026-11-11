import Config

config :backoffice, ecto_repos: [Backoffice.Repo]

config :backoffice, Backoffice.Repo,
  database: "backoffice_#{config_env()}",
  username: "kyc",
  password: "kyc",
  hostname: "localhost",
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  migration_source: "schema_migrations",
  log: false

config :backoffice, BackofficeWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: BackofficeWeb.ErrorJSON]],
  secret_key_base: String.duplicate("local-backoffice-only-", 4)

config :aike_storage,
  repo: DocumentOcr.Repo,
  adapter: AikeStorage.Adapter.S3,
  local_root: Path.expand("../var/uploads", __DIR__),
  s3: [
    endpoint: "http://127.0.0.1:8333",
    bucket: "aike-dev",
    region: "us-east-1",
    access_key_id: "aike-local",
    secret_access_key: "aike-local-secret"
  ],
  retention_seconds: 2_592_000

config :document_ocr, ecto_repos: [DocumentOcr.Repo]

config :document_ocr, DocumentOcr.Repo,
  database: "document_ocr_#{config_env()}",
  username: "kyc",
  password: "kyc",
  hostname: "localhost",
  port: String.to_integer(System.get_env("PGPORT", "5432"))

config :document_ocr, Oban,
  repo: DocumentOcr.Repo,
  queues: [preprocess: 2, ocr: 2, default: 2, maintenance: 1, webhooks: 5],
  cron: [
    crontab: [
      {"*/5 * * * *", DocumentOcr.Workers.ReconcileDocuments},
      {"*/5 * * * *", DocumentOcr.Workers.ReconcileStorage}
    ]
  ],
  plugins: [{Oban.Plugins.Pruner, max_age: 86_400}]

config :document_ocr,
  storage: DocumentOcr.Storage.Fake,
  ocr_engine: DocumentOcr.OCR.Tesseract,
  ocr_engines: [
    {DocumentOcr.OCR.Fake, "fake-1"},
    {DocumentOcr.OCR.Tesseract, "tesseract-5-por-5"},
    {DocumentOcr.OCR.TesseractPython, "tesseract-5-por-1"}
  ],
  extractors: %{
    {"cnh", "fake-cnh-1"} => DocumentOcr.Extraction.CNH,
    {"cnh", "br-labels-3"} => DocumentOcr.Extraction.CNHLabels,
    {"rg", "br-labels-3"} => DocumentOcr.Extraction.RGLabels
  },
  pipeline_version: "2026.11.0",
  ocr_engine_version: "tesseract-5-por-5",
  extractor_version: "br-labels-3",
  storage_timeout_ms: 5_000,
  ocr_timeout_ms: 15_000,
  max_wait_seconds: 10,
  max_waiting_requests: 1_000,
  completion_poll_ms: 1_000,
  webhook_signing_key: "local-development-webhook-signing-key-0123456789",
  webhook_require_https: false,
  webhook_allow_private_targets: true,
  external_call_mode: :async

config :document_ocr, DocumentOcr.Repo, log: false

config :document_ocr, DocumentOcrWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: DocumentOcrWeb.ErrorJSON]],
  secret_key_base: String.duplicate("local-development-only-", 4)

config :phoenix, :json_library, Jason

config :document_classifier,
  storage: DocumentClassifier.Storage.Fake,
  engine: DocumentClassifier.Engine.Tesseract,
  engine_version: "tesseract-por-rules-4",
  service_account_auth_required: false

config :aike_vision, face_models_dir: Path.expand("../var/models", __DIR__)

config :biometrics, ecto_repos: [Biometrics.Repo]

config :biometrics, Biometrics.Repo,
  database: "biometrics_#{config_env()}",
  username: "kyc",
  password: "kyc",
  hostname: "localhost",
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  log: false

config :biometrics, Oban,
  name: Biometrics.Oban,
  repo: Biometrics.Repo,
  queues: [biometrics: 2, biometrics_maintenance: 1],
  cron: [crontab: [{"*/5 * * * *", Biometrics.Workers.Reconcile}]],
  plugins: [{Oban.Plugins.Pruner, max_age: 86_400}]

config :biometrics,
  engine: Biometrics.Engine.OpenCV,
  engine_version: "opencv-yunet2023mar-sface2021dec-1",
  decision: [approve_at: 0.5, review_at: 0.363],
  max_wait_seconds: 10,
  max_waiting_requests: 1_000,
  completion_poll_ms: 1_000,
  auth_required: false

config :document_ocr, auth_required: false
config :document_classifier, auth_required: false
config :document_ocr, service_account_auth_required: false
config :biometrics, service_account_auth_required: false

config :biometrics, BiometricsWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: BiometricsWeb.ErrorJSON]],
  secret_key_base: String.duplicate("local-biometrics-only-", 4)

config :document_classifier, DocumentClassifierWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: DocumentClassifierWeb.ErrorJSON]],
  secret_key_base: String.duplicate("local-classifier-only-", 4)

config :phoenix, :filter_parameters, {:keep, []}

config :logger, :default_formatter,
  metadata: [
    :event,
    :status,
    :status_class,
    :duration_ms,
    :method,
    :request_id,
    :document_id,
    :run_id,
    :app_id,
    :pipeline_version,
    :ocr_engine,
    :ocr_engine_version,
    :extractor_version,
    :stage,
    :service,
    :service_account_id,
    :delivery_id,
    :attempt
  ]

config :aike_auth,
  url: "http://localhost:4003/internal/v1/service-accounts/introspect",
  cache_ttl_seconds: 30

import_config "#{config_env()}.exs"
