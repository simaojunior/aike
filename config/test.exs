import Config
config :document_ocr, DocumentOcr.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :document_ocr, Oban, testing: :manual, queues: false, plugins: false
config :document_ocr, external_call_mode: :sync
config :biometrics, Biometrics.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :biometrics, Oban, testing: :manual, queues: false, plugins: false
config :document_classifier, DocumentClassifier.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :logger, level: :warning
