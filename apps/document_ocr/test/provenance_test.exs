defmodule DocumentOcr.AlternativeTestEngine do
  @behaviour DocumentOcr.OCR.Engine
  alias DocumentOcr.OCR.Fake

  @impl true
  def extract(bytes, opts) do
    send(self(), {:alternative_engine, bytes, opts})
    {:ok, raw} = Fake.extract(bytes, opts)
    [name | rest] = raw["text"]
    {:ok, %{"text" => [%{name | "text" => "ANA TESTE"} | rest]}}
  end
end

defmodule DocumentOcr.AlternativeTestExtractor do
  alias DocumentOcr.Extraction.CNH

  def extract(raw) do
    {:ok, data} = CNH.extract(raw)
    {:ok, update_in(data, ["fields", "full_name", "value"], &("ALT " <> &1))}
  end
end

defmodule DocumentOcr.ProvenanceTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: DocumentOcr.Repo
  import Plug.Test
  import Plug.Conn
  alias DocumentOcr.{Documents, ProcessingConfig, Repo}
  alias DocumentOcr.Documents.{Document, DocumentResult}
  alias DocumentOcr.Extraction.CNH
  alias DocumentOcr.OCR.Fake
  alias DocumentOcr.Workers
  alias Ecto.Adapters.SQL.Sandbox

  @keys [
    :ocr_engine,
    :ocr_engine_version,
    :extractor_version,
    :pipeline_version,
    :ocr_engines,
    :extractors
  ]
  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    original = Map.new(@keys, &{&1, Application.fetch_env!(:document_ocr, &1)})

    Application.put_env(
      :document_ocr,
      :ocr_engines,
      original.ocr_engines ++ [{DocumentOcr.AlternativeTestEngine, "alternative-1"}]
    )

    Application.put_env(
      :document_ocr,
      :extractors,
      Map.put(
        original.extractors,
        {"cnh", "alternative-extractor-1"},
        DocumentOcr.AlternativeTestExtractor
      )
    )

    on_exit(fn ->
      Enum.each(original, fn {key, value} -> Application.put_env(:document_ocr, key, value) end)
    end)

    :ok
  end

  defp attrs do
    %{
      app_id: "test",
      external_id: "provenance",
      document_type: "cnh",
      country: "BR",
      request_id: "test",
      images: [%{side: "front", source_key: "fake/front.jpg"}]
    }
  end

  defp create do
    {:ok, %{document: document}} = Documents.create_document(attrs())
    document
  end

  defp alternative do
    Application.put_env(:document_ocr, :ocr_engine, DocumentOcr.AlternativeTestEngine)
    Application.put_env(:document_ocr, :ocr_engine_version, "alternative-1")
    Application.put_env(:document_ocr, :extractor_version, "alternative-extractor-1")
    Application.put_env(:document_ocr, :pipeline_version, "test-pipeline-2")
  end

  test "an alternative configured engine completes through unchanged workers and HTTP" do
    alternative()

    body = %{
      "appId" => "test",
      "externalId" => "alternative",
      "document" => %{"type" => "cnh", "country" => "BR"},
      "images" => [
        %{"side" => "front", "image" => Base.encode64("fake/front.jpg")}
      ]
    }

    response =
      conn(:post, "/v1/extractions", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> DocumentOcrWeb.Endpoint.call([])

    assert response.status == 202
    id = Jason.decode!(response.resp_body)["id"]
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :preprocess)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :ocr)
    assert_received {:alternative_engine, "fake/front.jpg", opts}
    assert opts[:document_type] == "cnh"
    assert opts[:engine_version] == "alternative-1"
    assert %{success: 3, failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)
    document = Documents.get_document!(id)
    assert document.status == "completed"
    assert document.result.ocr_engine == "DocumentOcr.AlternativeTestEngine"
    assert document.result.ocr_engine_version == "alternative-1"
    assert document.result.extractor_version == "alternative-extractor-1"
    assert document.result.pipeline_version == "test-pipeline-2"
    response = conn(:get, "/v1/extractions/#{id}") |> DocumentOcrWeb.Endpoint.call([])
    assert response.status == 200

    assert hd(Jason.decode!(response.resp_body)["data"])["person"]["name"]["value"] ==
             "ALT ANA TESTE"
  end

  test "configuration changes between creation, OCR and persistence never relabel a run" do
    first = create()
    alternative()
    second = create()
    assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :preprocess)
    assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :ocr)
    Application.put_env(:document_ocr, :ocr_engine_version, "future-version")
    Application.put_env(:document_ocr, :extractor_version, "future-extractor")
    Application.put_env(:document_ocr, :pipeline_version, "future-pipeline")
    assert %{success: 6, failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)

    for document <- [first, second] do
      stored = Documents.get_document!(document.id)
      assert stored.status == "completed"
      assert ProcessingConfig.metadata(stored.result) == ProcessingConfig.metadata(document)
    end

    assert Documents.get_document!(first.id).result.data["fields"]["full_name"]["value"] ==
             "NARUTO UZUMAKI"

    assert Documents.get_document!(second.id).result.data["fields"]["full_name"]["value"] ==
             "ALT ANA TESTE"
  end

  test "retry uses the pinned engine and never falls back when registration is removed" do
    alternative()
    document = create()
    Application.put_env(:document_ocr, :ocr_engine, Fake)
    Application.put_env(:document_ocr, :ocr_engine_version, "fake-1")
    registered = Application.fetch_env!(:document_ocr, :ocr_engines)
    Application.put_env(:document_ocr, :ocr_engines, [{Fake, "fake-1"}])
    assert %{success: 1} = Oban.drain_queue(queue: :preprocess)
    assert %{failure: 1, success: 0} = Oban.drain_queue(queue: :ocr)
    assert Documents.get_document!(document.id).status == "processing"
    assert Documents.artifact(document.id, "raw_ocr") == nil
    refute_received {:alternative_engine, _, _}
    Application.put_env(:document_ocr, :ocr_engines, registered)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :ocr, with_scheduled: true)
    assert_received {:alternative_engine, _, _}
    assert %{success: 3, failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)
    assert Documents.get_document!(document.id).result.ocr_engine_version == "alternative-1"
    assert Repo.aggregate(DocumentResult, :count) == 1
  end

  test "unregistered or empty versions prevent document/job creation" do
    for {key, value} <- [
          {:ocr_engine_version, "unregistered"},
          {:extractor_version, "unregistered"},
          {:pipeline_version, ""}
        ] do
      original = Application.fetch_env!(:document_ocr, key)
      Application.put_env(:document_ocr, key, value)
      assert {:error, :invalid_processing_configuration} = Documents.create_document(attrs())
      Application.put_env(:document_ocr, key, original)
    end

    assert Repo.aggregate(Document, :count) == 0
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
  end

  test "caller supplied provenance is ignored in favor of trusted configuration" do
    spoofed =
      Map.merge(attrs(), %{
        pipeline_version: "spoofed",
        ocr_engine: "Some.Module",
        ocr_engine_version: "spoofed",
        extractor_version: "spoofed"
      })

    {:ok, %{document: document}} = Documents.create_document(spoofed)
    assert document.pipeline_version == "2026.11.0"
    assert document.ocr_engine == "DocumentOcr.OCR.Fake"
    assert document.ocr_engine_version == "fake-1"
    assert document.extractor_version == "fake-cnh-1"

    versions =
      Map.take(spoofed, [:pipeline_version, :ocr_engine, :ocr_engine_version, :extractor_version])

    assert Document.changeset(document, versions).changes == %{}
  end

  test "legacy pending documents do not silently acquire today's engine versions" do
    document = create()

    document
    |> Ecto.Changeset.change(ocr_engine: nil, ocr_engine_version: nil, extractor_version: nil)
    |> Repo.update!()

    assert %{failure: 1} = Oban.drain_queue(queue: :preprocess)
    assert %{failure: 1} = Oban.drain_queue(queue: :preprocess, with_scheduled: true)
    assert %{discard: 1} = Oban.drain_queue(queue: :preprocess, with_scheduled: true)
    assert Documents.get_document!(document.id).status == "failed"
    assert Repo.aggregate(DocumentResult, :count) == 0
    assert Documents.artifact(document.id, "preprocessed") == nil
  end

  test "persisting again copies captured metadata despite later config changes" do
    document = create()
    {:ok, raw} = Fake.extract("bytes", [])
    {:ok, data} = CNH.extract(raw)
    data = DocumentOcr.Validation.validate_result(data)
    {:ok, original} = Documents.save_result(document, data)
    alternative()
    {:ok, _} = Documents.save_result(document, data)
    assert Repo.aggregate(DocumentResult, :count) == 1

    assert ProcessingConfig.metadata(Documents.get_document!(document.id).result) ==
             ProcessingConfig.metadata(original)
  end

  test "missing extractor version retries rather than using the current default" do
    alternative()
    document = create()
    assert %{success: 1} = Oban.drain_queue(queue: :preprocess)
    assert %{success: 1} = Oban.drain_queue(queue: :ocr)
    extractors = Application.fetch_env!(:document_ocr, :extractors)
    Application.put_env(:document_ocr, :extractor_version, "fake-cnh-1")

    Application.put_env(
      :document_ocr,
      :extractors,
      Map.delete(extractors, {"cnh", "alternative-extractor-1"})
    )

    assert %{failure: 1, success: 0} = Oban.drain_queue(queue: :default)
    assert Documents.artifact(document.id, "extracted") == nil
    assert Repo.aggregate(DocumentResult, :count) == 0
    Application.put_env(:document_ocr, :extractors, extractors)

    assert %{success: 3, failure: 0} =
             Oban.drain_queue(queue: :default, with_scheduled: true, with_recursion: true)

    assert Documents.get_document!(document.id).result.extractor_version ==
             "alternative-extractor-1"
  end

  test "invalid server-side configuration returns 503 without creating work" do
    Application.put_env(:document_ocr, :ocr_engine_version, "unregistered")

    body = %{
      "appId" => "test",
      "externalId" => "bad-config",
      "document" => %{"type" => "cnh", "country" => "BR"},
      "images" => [
        %{"side" => "front", "image" => Base.encode64("fake/front.jpg")}
      ]
    }

    response =
      conn(:post, "/v1/extractions", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> DocumentOcrWeb.Endpoint.call([])

    assert response.status == 503

    assert %{
             "code" => "service_unavailable",
             "detail" => "The service is temporarily unavailable."
           } = Jason.decode!(response.resp_body)

    assert Repo.aggregate(Document, :count) == 0
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
  end

  test "legacy completed results remain available without guessed document metadata" do
    document = create()
    assert %{success: 1} = Oban.drain_queue(queue: :preprocess)
    assert %{success: 1} = Oban.drain_queue(queue: :ocr)
    assert %{success: 3} = Oban.drain_queue(queue: :default, with_recursion: true)
    stored = Documents.get_document!(document.id)

    stored
    |> Ecto.Changeset.change(ocr_engine: nil, ocr_engine_version: nil, extractor_version: nil)
    |> Repo.update!()

    alternative()
    assert :ok = perform_job(Workers.CompleteDocument, Documents.job_args(document))
    current = Documents.get_document!(document.id)
    assert current.result == stored.result
    assert current.ocr_engine == nil
    assert current.status == "completed"

    response = conn(:get, "/v1/extractions/#{document.id}") |> DocumentOcrWeb.Endpoint.call([])

    assert response.status == 200
  end
end
