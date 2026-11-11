import Config

config :document_classifier,
  engine: DocumentClassifier.Engine.Fake,
  engine_version: "fake-1"

config :document_ocr,
  ocr_engine: DocumentOcr.OCR.Fake,
  ocr_engine_version: "fake-1",
  extractor_version: "fake-cnh-1"

config :backoffice, Backoffice.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :document_ocr, DocumentOcr.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :document_ocr, Oban, testing: :manual, queues: false, plugins: false, cron: false
config :document_ocr, external_call_mode: :sync
config :document_ocr, completion_poll_ms: 50

config :biometrics,
  engine: Biometrics.Engine.Fake,
  engine_version: "fake-1",
  completion_poll_ms: 50

config :biometrics, Biometrics.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :biometrics, Oban, testing: :manual, queues: false, plugins: false, cron: false
config :logger, level: :warning

config :aike_storage, adapter: AikeStorage.Adapter.Fake
config :aike_auth, cache_ttl_seconds: 0
