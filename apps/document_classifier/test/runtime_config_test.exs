defmodule Aike.RuntimeConfigTest do
  use ExUnit.Case, async: false
  @runtime Path.expand("../../../config/runtime.exs", __DIR__)
  @keys ~w(RELEASE_NAME CLASSIFIER_SERVICE_TOKEN CLASSIFIER_SECRET_KEY_BASE SERVICE_TOKEN SECRET_KEY_BASE DATABASE_URL CLASSIFIER_PORT PORT PHX_SERVER BACKOFFICE_ADMIN_TOKEN BACKOFFICE_BOOTSTRAP_TOKEN BACKOFFICE_SECRET_KEY_BASE BACKOFFICE_DATABASE_URL BACKOFFICE_PORT AIKE_AUTH_TOKEN BACKOFFICE_AUTH_URL AIKE_STORAGE_ADAPTER S3_ENDPOINT S3_BUCKET S3_REGION S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY WEBHOOK_SIGNING_KEY AIKE_HTTP_IP BIOMETRICS_DATABASE_URL BIOMETRICS_SERVICE_TOKEN BIOMETRICS_SECRET_KEY_BASE)

  setup do
    original = Map.new(@keys, &{&1, System.get_env(&1)})
    Enum.each(@keys, &System.delete_env/1)
    System.put_env("AIKE_AUTH_TOKEN", "internal-test-token")

    System.put_env(
      "BACKOFFICE_AUTH_URL",
      "http://localhost:4003/internal/v1/service-accounts/introspect"
    )

    for {key, value} <- s3_env(), do: System.put_env(key, value)
    System.put_env("WEBHOOK_SIGNING_KEY", String.duplicate("w", 32))

    on_exit(fn ->
      for {key, value} <- original do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    :ok
  end

  defp read, do: Config.Reader.read!(@runtime, env: :prod)

  defp s3_env do
    [
      {"S3_ENDPOINT", "https://storage.example"},
      {"S3_BUCKET", "documents"},
      {"S3_ACCESS_KEY_ID", "key-id"},
      {"S3_SECRET_ACCESS_KEY", "key-secret"}
    ]
  end

  defp ocr_release do
    System.put_env("RELEASE_NAME", "document_ocr")
    System.put_env("SERVICE_TOKEN", "fixture-token")
    System.put_env("SECRET_KEY_BASE", String.duplicate("o", 64))
    System.put_env("DATABASE_URL", "ecto://kyc:kyc@localhost/document_ocr_test")
  end

  test "document releases require S3 storage settings in production" do
    ocr_release()
    config = read()
    assert config[:aike_storage][:s3][:bucket] == "documents"
    assert config[:aike_storage][:s3][:region] == "auto"

    for {key, _} <- s3_env() do
      for {name, value} <- s3_env(), do: System.put_env(name, value)
      System.delete_env(key)
      assert_raise ArgumentError, ~r/#{key}/, fn -> read() end
    end
  end

  test "endpoints listen on loopback by default and on AIKE_HTTP_IP when set" do
    ocr_release()
    assert read()[:document_ocr][DocumentOcrWeb.Endpoint][:http][:ip] == {127, 0, 0, 1}

    System.put_env("AIKE_HTTP_IP", "0.0.0.0")
    assert read()[:document_ocr][DocumentOcrWeb.Endpoint][:http][:ip] == {0, 0, 0, 0}

    System.put_env("AIKE_HTTP_IP", "::")
    assert read()[:document_ocr][DocumentOcrWeb.Endpoint][:http][:ip] == {0, 0, 0, 0, 0, 0, 0, 0}

    System.put_env("AIKE_HTTP_IP", "konoha")
    assert_raise ArgumentError, ~r/AIKE_HTTP_IP/, fn -> read() end
  end

  test "the OCR release requires a webhook signing key of at least 32 bytes" do
    ocr_release()
    assert read()[:document_ocr][:webhook_signing_key] == String.duplicate("w", 32)

    System.put_env("WEBHOOK_SIGNING_KEY", "short")
    assert_raise ArgumentError, ~r/WEBHOOK_SIGNING_KEY/, fn -> read() end

    System.delete_env("WEBHOOK_SIGNING_KEY")
    assert_raise ArgumentError, ~r/WEBHOOK_SIGNING_KEY/, fn -> read() end
  end

  test "local storage and storage-free releases need no S3 settings" do
    Enum.each(s3_env(), fn {key, _} -> System.delete_env(key) end)
    ocr_release()
    System.put_env("AIKE_STORAGE_ADAPTER", "local")
    assert read()[:aike_storage][:adapter] == AikeStorage.Adapter.Local

    System.delete_env("AIKE_STORAGE_ADAPTER")
    System.put_env("RELEASE_NAME", "document_classifier")
    System.put_env("CLASSIFIER_SERVICE_TOKEN", "fixture-token")
    System.put_env("CLASSIFIER_SECRET_KEY_BASE", String.duplicate("c", 64))
    refute read()[:aike_storage][:s3]
  end

  test "classifier release has no OCR environment dependency" do
    System.put_env("RELEASE_NAME", "document_classifier")
    System.put_env("CLASSIFIER_SERVICE_TOKEN", "fixture-token")
    System.put_env("CLASSIFIER_SECRET_KEY_BASE", String.duplicate("c", 64))
    config = read()
    assert config[:document_classifier][:service_token] == "fixture-token"
    refute Keyword.has_key?(config, :document_ocr)
  end

  test "OCR release ignores invalid classifier settings" do
    System.put_env("RELEASE_NAME", "document_ocr")
    System.put_env("SERVICE_TOKEN", "fixture-token")
    System.put_env("SECRET_KEY_BASE", String.duplicate("o", 64))
    System.put_env("DATABASE_URL", "ecto://kyc:kyc@localhost/document_ocr_test")
    System.put_env("CLASSIFIER_PORT", "not-a-port")
    config = read()
    assert config[:document_ocr][:service_token] == "fixture-token"
    refute Keyword.has_key?(config, :document_classifier)
  end

  test "production rejects missing and blank service tokens" do
    System.put_env("RELEASE_NAME", "document_classifier")
    System.put_env("CLASSIFIER_SECRET_KEY_BASE", String.duplicate("c", 64))

    for token <- [nil, "", "   "] do
      if token,
        do: System.put_env("CLASSIFIER_SERVICE_TOKEN", token),
        else: System.delete_env("CLASSIFIER_SERVICE_TOKEN")

      assert_raise ArgumentError, ~r/CLASSIFIER_SERVICE_TOKEN/, fn -> read() end
    end
  end

  test "shared fallback remains valid and unknown release names fail closed" do
    System.put_env("BACKOFFICE_ADMIN_TOKEN", "admin-fixture-token")
    System.put_env("BACKOFFICE_SECRET_KEY_BASE", String.duplicate("b", 64))
    System.put_env("SERVICE_TOKEN", "shared-fixture-token")
    System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))
    System.put_env("DATABASE_URL", "ecto://kyc:kyc@localhost/document_ocr_test")
    System.put_env("BACKOFFICE_DATABASE_URL", "ecto://kyc:kyc@localhost/backoffice_test")
    System.put_env("BIOMETRICS_DATABASE_URL", "ecto://kyc:kyc@localhost/biometrics_test")
    config = read()
    assert config[:document_classifier][:service_token] == "shared-fixture-token"
    assert config[:document_ocr][:service_token] == "shared-fixture-token"
    System.put_env("RELEASE_NAME", "typo")
    assert_raise ArgumentError, ~r/Unknown Aike release/, fn -> read() end
  end

  test "backoffice release only requires its own runtime settings" do
    System.put_env("RELEASE_NAME", "backoffice")
    System.put_env("BACKOFFICE_ADMIN_TOKEN", "admin-fixture-token")
    System.put_env("BACKOFFICE_SECRET_KEY_BASE", String.duplicate("b", 64))
    System.put_env("BACKOFFICE_DATABASE_URL", "ecto://kyc:kyc@localhost/document_ocr_test")
    System.put_env("PORT", "not-a-port")
    System.put_env("CLASSIFIER_PORT", "not-a-port")
    config = read()
    assert config[:backoffice][:bootstrap_token] == "admin-fixture-token"
    refute config[:backoffice][:admin_token]
    assert config[:backoffice][BackofficeWeb.Endpoint][:http][:port] == 4003

    for app <- [:document_ocr, :document_classifier, :biometrics] do
      refute Keyword.has_key?(config, app)
    end

    System.delete_env("BACKOFFICE_ADMIN_TOKEN")
    refute read()[:backoffice][:bootstrap_token]
  end

  test "backoffice cannot silently fall back to the processing database" do
    System.put_env("RELEASE_NAME", "backoffice")
    System.put_env("DATABASE_URL", "ecto://kyc:kyc@localhost/document_ocr_test")
    assert_raise ArgumentError, ~r/BACKOFFICE_DATABASE_URL/, fn -> read() end
  end

  test "biometrics uses its own database and never falls back to the OCR database" do
    System.put_env("RELEASE_NAME", "biometrics")
    System.put_env("BIOMETRICS_SERVICE_TOKEN", "fixture-token")
    System.put_env("BIOMETRICS_SECRET_KEY_BASE", String.duplicate("b", 64))
    System.put_env("DATABASE_URL", "ecto://kyc:kyc@localhost/document_ocr_test")
    assert_raise ArgumentError, ~r/BIOMETRICS_DATABASE_URL/, fn -> read() end

    System.put_env("BIOMETRICS_DATABASE_URL", "ecto://kyc:kyc@localhost/biometrics_test")
    assert read()[:biometrics][Biometrics.Repo][:url] =~ "biometrics_test"
  end

  test "processing releases require the identity service configuration" do
    System.put_env("RELEASE_NAME", "document_classifier")
    System.put_env("CLASSIFIER_SERVICE_TOKEN", "fixture-token")
    System.put_env("CLASSIFIER_SECRET_KEY_BASE", String.duplicate("c", 64))
    System.delete_env("AIKE_AUTH_TOKEN")
    assert_raise ArgumentError, ~r/AIKE_AUTH_TOKEN/, fn -> read() end
  end
end
