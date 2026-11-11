import Config

auth_required = true

config :document_ocr, service_account_auth_required: auth_required
config :document_classifier, service_account_auth_required: auth_required
config :biometrics, service_account_auth_required: auth_required
