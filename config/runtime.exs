import Config

# Mix starts the umbrella by default; named releases configure only their service.
services =
  case System.get_env("RELEASE_NAME") do
    nil -> [:document_ocr, :document_classifier, :biometrics]
    "document_ocr" -> [:document_ocr]
    "document_classifier" -> [:document_classifier]
    "biometrics" -> [:biometrics]
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

if :biometrics in services do
  config :biometrics, BiometricsWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("BIOMETRICS_PORT", "4002"))]

  if System.get_env("PHX_SERVER") == "true" do
    config :biometrics, BiometricsWeb.Endpoint, server: true
  end

  if config_env() == :prod do
    config :biometrics, :service_token, required_env.("BIOMETRICS_SERVICE_TOKEN", "SERVICE_TOKEN")
    config :biometrics, :auth_required, true
    config :biometrics, :service_account_auth_required, true
    config :biometrics, Biometrics.Repo, url: required_env.("DATABASE_URL", nil)

    config :biometrics, BiometricsWeb.Endpoint,
      secret_key_base: required_env.("BIOMETRICS_SECRET_KEY_BASE", "SECRET_KEY_BASE")
  end
end

if :document_classifier in services do
  config :document_classifier, DocumentClassifierWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("CLASSIFIER_PORT", "4001"))]

  if System.get_env("PHX_SERVER") == "true" do
    config :document_classifier, DocumentClassifierWeb.Endpoint, server: true
  end

  if config_env() == :prod do
    config :document_classifier,
           :service_token,
           required_env.("CLASSIFIER_SERVICE_TOKEN", "SERVICE_TOKEN")

    config :document_classifier, :service_account_auth_required, true

    if database_url = System.get_env("DATABASE_URL") do
      config :document_classifier, DocumentClassifier.Repo, url: database_url
    end

    config :document_classifier, DocumentClassifierWeb.Endpoint,
      secret_key_base: required_env.("CLASSIFIER_SECRET_KEY_BASE", "SECRET_KEY_BASE")
  end
end

if :document_ocr in services do
  config :document_ocr, DocumentOcrWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))]

  if System.get_env("PHX_SERVER") == "true" do
    config :document_ocr, DocumentOcrWeb.Endpoint, server: true
  end

  if config_env() == :prod do
    config :document_ocr, :service_token, required_env.("SERVICE_TOKEN", nil)
    config :document_ocr, :service_account_auth_required, true
    config :document_ocr, DocumentOcr.Repo, url: required_env.("DATABASE_URL", nil)

    config :document_ocr, DocumentOcrWeb.Endpoint,
      secret_key_base: required_env.("SECRET_KEY_BASE", nil)
  end
end
