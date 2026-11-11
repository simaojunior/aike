defmodule DocumentClassifier.CountingTestEngine do
  @behaviour DocumentClassifier.Engine
  def classify(bytes, opts) do
    send(self(), {:classified, bytes})

    if bytes == "failure",
      do: {:error, :unavailable},
      else: DocumentClassifier.Engine.Fake.classify(bytes, opts)
  end
end

defmodule DocumentClassifier.StatelessClassificationTest do
  use ExUnit.Case, async: false
  alias DocumentClassifier.Classifications

  setup do
    original = Application.fetch_env!(:document_classifier, :engine)
    version = Application.fetch_env!(:document_classifier, :engine_version)
    Application.put_env(:document_classifier, :engine, DocumentClassifier.CountingTestEngine)

    on_exit(fn ->
      Application.put_env(:document_classifier, :engine, original)
      Application.put_env(:document_classifier, :engine_version, version)
    end)

    :ok
  end

  defp classify(bytes, company \\ "company-a"),
    do: Classifications.classify(%{"image" => Base.encode64(bytes)}, company)

  test "each request evaluates its bytes without retaining previous results" do
    assert {:ok, bad} = classify("fake:bad_quality")
    refute bad["quality"]["acceptable"]
    assert_received {:classified, "fake:bad_quality"}

    assert {:ok, ^bad} = classify("fake:bad_quality")
    assert_received {:classified, _}

    assert {:ok, good} = classify("new-good-photo")
    assert good["quality"]["acceptable"]
    assert_received {:classified, "new-good-photo"}
  end

  test "company and engine version do not introduce persistence" do
    assert {:ok, _} = classify("same-photo")
    assert_received {:classified, "same-photo"}
    assert {:ok, _} = classify("same-photo", "company-b")
    assert_received {:classified, "same-photo"}

    Application.put_env(:document_classifier, :engine_version, "new-version")
    assert {:ok, _} = classify("same-photo")
    assert_received {:classified, "same-photo"}
  end

  test "technical errors allow a fresh subsequent attempt" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        for _ <- 1..2 do
          assert {:error, :service_unavailable} = classify("failure")
          assert_received {:classified, "failure"}
        end
      end)

    assert log =~ "engine_failed"
  end

  test "multipart and JSON independently classify the same bytes" do
    assert {:ok, result} = classify("same-photo")
    assert_received {:classified, "same-photo"}
    path = Path.join(System.tmp_dir!(), "classifier-reuse-#{System.unique_integer([:positive])}")
    File.write!(path, "same-photo")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, ^result} =
             Classifications.classify(
               %Plug.Upload{path: path, filename: "renamed.jpg"},
               "company-a"
             )

    assert_received {:classified, _}
  end
end
