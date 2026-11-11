defmodule DocumentClassifier.TestEngineFailure do
  @behaviour DocumentClassifier.Engine
  def classify(_, _), do: {:error, "SECRET-IMAGE-CONTENT"}
end

defmodule DocumentClassifier.TestEngineRaise do
  @behaviour DocumentClassifier.Engine
  def classify(_, _), do: raise("SECRET-IMAGE-CONTENT")
end

defmodule DocumentClassifier.TestInvalidEngine do
  @behaviour DocumentClassifier.Engine
  def classify(_, _), do: {:ok, %{"confidence" => 2}}
end

defmodule DocumentClassifier.TestEngineOverloaded do
  @behaviour DocumentClassifier.Engine
  def classify(_, _), do: {:error, :overloaded}
end

defmodule DocumentClassifier.TestStorage do
  @behaviour DocumentClassifier.Storage
  def get(key) do
    send(self(), {:storage_called, key})
    {:ok, "synthetic-bytes"}
  end
end

defmodule DocumentClassifier.TestEngine do
  @behaviour DocumentClassifier.Engine
  def classify(bytes, opts) do
    send(self(), {:engine_called, bytes, opts})
    DocumentClassifier.Engine.Fake.classify("fake:rg_single", [])
  end
end

defmodule DocumentClassifier.ClassificationAPITest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn
  import ExUnit.CaptureLog

  setup do
    keys = [:storage, :engine, :service_token, :auth_required]
    original = Map.new(keys, &{&1, Application.fetch_env(:document_classifier, &1)})

    on_exit(fn ->
      for {key, value} <- original do
        case value do
          {:ok, value} -> Application.put_env(:document_classifier, key, value)
          :error -> Application.delete_env(:document_classifier, key)
        end
      end
    end)

    :ok
  end

  defp payload(key) do
    fixture = key |> Path.basename(".jpg") |> String.replace("-", "_")
    %{"image" => Base.encode64("fake:" <> fixture)}
  end

  defp request(body, headers \\ []) do
    conn =
      conn(:post, "/v1/classifications", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")

    conn =
      Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

    DocumentClassifierWeb.Endpoint.call(conn, [])
  end

  test "POST classifies default CNH front without user or onboarding state" do
    response = request(payload("kyc/session-123/frame-001.jpg"))
    assert response.status == 200
    assert get_resp_header(response, "content-type") == ["application/json; charset=utf-8"]
    assert [_] = get_resp_header(response, "x-request-id")

    body = Jason.decode!(response.resp_body)
    assert body["version"] == "v1"
    assert is_binary(body["id"])

    assert body["data"] == [
             %{
               "classification" => %{
                 "type" => "drivers_license",
                 "country" => "BRA",
                 "side" => "only_front",
                 "confidence" => 0.99
               },
               "quality" => %{"isAccepted" => true, "issues" => []},
               "fileInfo" => %{"fieldname" => "image"}
             }
           ]

    bytes = "fake:frame_001"

    assert [
             %{
               "fieldname" => "image",
               "name" => nil,
               "size" => byte_size(bytes),
               "mimetype" => nil,
               "sha256" => Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
             }
           ] == body["metadata"]["filesInfo"]

    assert is_integer(body["metadata"]["processingTimeMs"])
  end

  test "multipart image payload is classified without object storage" do
    path = Path.join(System.tmp_dir!(), "classifier-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "fake:rg_single")

    try do
      response =
        conn(:post, "/v1/classifications", %{
          "file" => %Plug.Upload{path: path, filename: "capture.jpg", content_type: "image/jpeg"}
        })
        |> DocumentClassifierWeb.Endpoint.call([])

      assert response.status == 200
      body = Jason.decode!(response.resp_body)
      ordered = Jason.decode!(response.resp_body, objects: :ordered_objects)
      assert Enum.map(ordered.values, &elem(&1, 0)) == ~w(id version data metadata)
      [entry] = ordered["data"]
      assert Enum.map(entry.values, &elem(&1, 0)) == ~w(classification quality fileInfo)

      assert Enum.map(entry["classification"].values, &elem(&1, 0)) ==
               ~w(type country side confidence)

      assert Enum.map(entry["quality"].values, &elem(&1, 0)) == ~w(isAccepted issues)

      assert Enum.map(ordered["metadata"].values, &elem(&1, 0)) ==
               ~w(filesInfo processingTimeMs)

      [file] = ordered["metadata"]["filesInfo"]
      assert Enum.map(file.values, &elem(&1, 0)) == ~w(fieldname name size mimetype sha256)
      assert body["version"] == "v1"
      assert Enum.at(body["data"], 0)["classification"]["type"] == "id_card"
      assert Enum.at(body["metadata"]["filesInfo"], 0)["fieldname"] == "file"
    after
      File.rm(path)
    end
  end

  test "HTTP fixtures support CNH back, RG front/back/single and unknown" do
    for {key, type, side} <- [
          {"fake/cnh-back.jpg", "drivers_license", "only_back"},
          {"fake/rg-front.jpg", "id_card", "only_front"},
          {"fake/rg-back.jpg", "id_card", "only_back"},
          {"fake/rg-single.jpg", "id_card", "front_and_back"}
        ] do
      response = request(payload(key))
      assert response.status == 200
      [%{"classification" => classification}] = Jason.decode!(response.resp_body)["data"]
      assert {classification["type"], classification["side"]} == {type, side}
      assert classification["country"] == "BRA"
    end
  end

  test "unknown and bad quality remain successful classification responses" do
    unknown = request(payload("fake/unknown.jpg"))
    assert unknown.status == 200
    assert Jason.decode!(unknown.resp_body)["data"] == []
    bad = request(payload("fake/bad-quality.jpg"))
    assert bad.status == 200
    [entry] = Jason.decode!(bad.resp_body)["data"]

    assert entry["quality"] == %{"isAccepted" => false, "issues" => ["blur", "glare"]}
    assert entry["classification"]["confidence"] == 0.98
  end

  test "missing and invalid source fields never reach storage" do
    Application.put_env(:document_classifier, :storage, DocumentClassifier.TestStorage)

    for body <- [
          %{},
          %{"source" => nil},
          %{"source" => []},
          %{"source" => %{"type" => "object_storage"}},
          %{"source" => %{"key" => "x"}},
          %{"source" => %{"type" => "url", "key" => "https://example.test/x"}},
          %{"source" => %{"type" => "object_storage", "key" => "fake/front.jpg"}},
          %{"image" => nil},
          %{"image" => 123},
          %{"image" => []},
          %{"image" => ""},
          %{"image" => "not base64!"}
        ] do
      response = request(body)
      assert response.status == 422
      assert %{"code" => "validation", "errors" => [_ | _]} = Jason.decode!(response.resp_body)
    end

    refute_received {:storage_called, _}
  end

  test "engine receives decoded image bytes without storage" do
    Application.put_env(:document_classifier, :storage, DocumentClassifier.TestStorage)
    Application.put_env(:document_classifier, :engine, DocumentClassifier.TestEngine)
    response = request(payload("private/object-key"))
    assert response.status == 200
    refute_received {:storage_called, _}
    assert_received {:engine_called, "fake:object_key", []}

    assert [%{"classification" => %{"type" => "id_card"}}] =
             Jason.decode!(response.resp_body)["data"]
  end

  test "an overloaded node answers 503 with Retry-After and logs no error" do
    Application.put_env(:document_classifier, :engine, DocumentClassifier.TestEngineOverloaded)

    log =
      capture_log(fn ->
        response = request(payload("kyc/session-1/frame-1.jpg"))
        assert response.status == 503
        assert get_resp_header(response, "retry-after") == ["2"]
        assert Jason.decode!(response.resp_body)["code"] == "service_unavailable"
      end)

    refute log =~ "classifier.failed"
  end

  test "adapter errors and exceptions return sanitized 503 without leaking data" do
    for {key, adapter} <- [
          {:engine, DocumentClassifier.TestEngineFailure},
          {:engine, DocumentClassifier.TestEngineRaise},
          {:engine, DocumentClassifier.TestInvalidEngine}
        ] do
      Application.put_env(:document_classifier, :storage, DocumentClassifier.Storage.Fake)
      Application.put_env(:document_classifier, :engine, DocumentClassifier.Engine.Fake)
      Application.put_env(:document_classifier, key, adapter)

      log =
        capture_log(fn ->
          response = request(payload("private/key"))
          assert response.status == 503

          assert %{
                   "code" => "service_unavailable",
                   "detail" => "The service is temporarily unavailable."
                 } = Jason.decode!(response.resp_body)
        end)

      refute log =~ "SECRET"
      refute log =~ "private/key"
    end
  end

  test "Bearer authentication is enforced when a service token is configured" do
    Application.put_env(:document_classifier, :service_token, "classifier-test-token")
    assert request(payload("x")).status == 401
    assert request(payload("x"), [{"authorization", "Bearer wrong"}]).status == 401
    assert request(payload("x"), [{"authorization", "Basic classifier-test-token"}]).status == 401

    assert request(payload("x"), [{"authorization", "Bearer classifier-test-token"}]).status ==
             200

    Application.put_env(:document_classifier, :service_token, "")
    assert request(payload("x"), [{"authorization", "Bearer "}]).status == 401
  end

  test "requests do not retain results from preceding classifications" do
    for key <- ["fake/unknown.jpg", "fake/bad-quality.jpg", "fake/cnh-back.jpg"] do
      assert request(payload(key)).status == 200
      response = request(payload("normal/front.jpg"))
      [entry] = Jason.decode!(response.resp_body)["data"]
      assert entry["classification"]["side"] == "only_front"
      assert entry["quality"]["isAccepted"]
    end
  end

  test "required authentication denies requests when the token is absent" do
    Application.delete_env(:document_classifier, :service_token)
    Application.put_env(:document_classifier, :auth_required, true)
    assert request(payload("x")).status == 401
  end
end
