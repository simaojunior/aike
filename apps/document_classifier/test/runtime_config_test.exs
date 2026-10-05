defmodule Aike.RuntimeConfigTest do
  use ExUnit.Case, async: false
  @runtime Path.expand("../../../config/runtime.exs", __DIR__)
  @keys ~w(RELEASE_NAME CLASSIFIER_SERVICE_TOKEN CLASSIFIER_SECRET_KEY_BASE SERVICE_TOKEN SECRET_KEY_BASE DATABASE_URL CLASSIFIER_PORT PORT PHX_SERVER)

  setup do
    original = Map.new(@keys, &{&1, System.get_env(&1)})
    Enum.each(@keys, &System.delete_env/1)

    on_exit(fn ->
      for {key, value} <- original do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    :ok
  end

  defp read, do: Config.Reader.read!(@runtime, env: :prod)

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
    System.put_env("SERVICE_TOKEN", "shared-fixture-token")
    System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))
    System.put_env("DATABASE_URL", "ecto://kyc:kyc@localhost/document_ocr_test")
    config = read()
    assert config[:document_classifier][:service_token] == "shared-fixture-token"
    assert config[:document_ocr][:service_token] == "shared-fixture-token"
    System.put_env("RELEASE_NAME", "typo")
    assert_raise ArgumentError, ~r/Unknown Aike release/, fn -> read() end
  end
end
