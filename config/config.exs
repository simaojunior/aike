import Config

config :aike_storage,
  repo: DocumentOcr.Repo,
  adapter: AikeStorage.Adapter.Fake,
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
  queues: [preprocess: 2, ocr: 2, default: 2],
  plugins: [Oban.Plugins.Pruner]

config :document_ocr,
  storage: DocumentOcr.Storage.Fake,
  ocr_engine: DocumentOcr.OCR.Fake,
  ocr_engines: [{DocumentOcr.OCR.Fake, "fake-1"}],
  extractors: %{{"cnh", "fake-cnh-1"} => DocumentOcr.Extraction.CNH},
  pipeline_version: "2026.11.0",
  ocr_engine_version: "fake-1",
  extractor_version: "fake-cnh-1",
  storage_timeout_ms: 5_000,
  ocr_timeout_ms: 15_000,
  external_call_mode: :async

config :document_ocr, DocumentOcr.Repo, log: false

config :document_ocr, DocumentOcrWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: DocumentOcrWeb.ErrorJSON]],
  secret_key_base: String.duplicate("local-development-only-", 4)

config :phoenix, :json_library, Jason

config :document_classifier,
  storage: DocumentClassifier.Storage.Fake,
  engine: DocumentClassifier.Engine.Fake,
  service_account_auth_required: false,
  service_account_repo: DocumentClassifier.Repo

config :document_classifier, ecto_repos: [DocumentClassifier.Repo]

config :document_classifier, DocumentClassifier.Repo,
  database: "document_ocr_#{config_env()}",
  username: "kyc",
  password: "kyc",
  hostname: "localhost",
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  migration_source: "schema_migrations",
  log: false

config :biometrics, ecto_repos: [Biometrics.Repo]

config :biometrics, Biometrics.Repo,
  database: "document_ocr_#{config_env()}",
  username: "kyc",
  password: "kyc",
  hostname: "localhost",
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  migration_source: "schema_migrations",
  log: false

config :biometrics, Oban,
  name: Biometrics.Oban,
  repo: Biometrics.Repo,
  queues: [biometrics: 2],
  plugins: [Oban.Plugins.Pruner]

config :biometrics,
  engine: Biometrics.Engine.Fake,
  auth_required: false

config :document_ocr, auth_required: false
config :document_classifier, auth_required: false
config :document_ocr, service_account_auth_required: false, service_account_repo: DocumentOcr.Repo
config :biometrics, service_account_auth_required: false, service_account_repo: Biometrics.Repo

config :biometrics, BiometricsWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: String.duplicate("local-biometrics-only-", 4)

config :document_classifier, DocumentClassifierWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: DocumentClassifierWeb.ErrorJSON]],
  secret_key_base: String.duplicate("local-classifier-only-", 4)

config :phoenix, :filter_parameters, {:keep, []}

config :logger, :default_formatter,
  metadata: [
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
    :service_account_id
  ]

import_config "#{config_env()}.exs"
