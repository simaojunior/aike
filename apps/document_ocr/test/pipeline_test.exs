defmodule DocumentOcr.TestStorageFailure do
  @behaviour DocumentOcr.Storage
  def get(_), do: {:error, :unavailable}
end

defmodule DocumentOcr.TestOCRFailure do
  @behaviour DocumentOcr.OCR.Engine
  def extract(_, _), do: {:error, :unavailable}
end

defmodule DocumentOcr.TestSideStorage do
  @behaviour DocumentOcr.Storage
  def get(key), do: {:ok, key}
end

defmodule DocumentOcr.TestSideOCR do
  @behaviour DocumentOcr.OCR.Engine
  def extract(bytes, opts) do
    {:ok, raw} = DocumentOcr.OCR.Fake.extract(bytes, opts)
    [name | rest] = raw["text"]
    text = if bytes == "front.jpg", do: "FRONT PERSON", else: "BACK PERSON"
    {:ok, %{"text" => [%{name | "text" => text} | rest]}}
  end
end

defmodule DocumentOcr.TestRGOCR do
  @behaviour DocumentOcr.OCR.Engine
  def extract("front.jpg", _opts),
    do: {:ok, %{"text" => [line("SECRETARIA DA SEGURANCA PUBLICA", 40, 40)]}}

  def extract("back.jpg", _opts) do
    {:ok,
     %{
       "text" => [
         line("REGISTRO GERAL 12.345.678-9 DATA DE EXPEDICAO 19/12/2018", 40, 40),
         line("NOME", 40, 100),
         line("NARUTO UZUMAKI", 40, 140),
         line("NATURALIDADE", 40, 200),
         line("PORTO ALEGRE RS", 40, 240),
         line("12/03/1990", 600, 300),
         line("CPF", 40, 400),
         line("529.982.247-25", 40, 440)
       ]
     }}
  end

  defp line(text, left, top),
    do: %{"text" => text, "confidence" => 0.95, "bbox" => [left, top, 300, 30], "source" => 0}
end

defmodule DocumentOcr.PipelineTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: DocumentOcr.Repo
  import Plug.Test
  import Plug.Conn
  alias DocumentOcr.{Documents, Repo}
  alias DocumentOcr.Documents.{Document, DocumentResult, DocumentArtifact}
  alias DocumentOcr.Workers

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    original_engines = Application.fetch_env!(:document_ocr, :ocr_engines)
    original_storage = Application.fetch_env!(:aike_storage, :adapter)

    Application.put_env(
      :document_ocr,
      :ocr_engines,
      original_engines ++
        [{DocumentOcr.TestOCRFailure, "fake-1"}, {DocumentOcr.TestSideOCR, "fake-1"}]
    )

    on_exit(fn ->
      Application.put_env(:aike_storage, :adapter, original_storage)
      Application.put_env(:document_ocr, :storage, DocumentOcr.Storage.Fake)
      Application.put_env(:document_ocr, :ocr_engine, DocumentOcr.OCR.Fake)
      Application.put_env(:document_ocr, :ocr_engines, original_engines)
    end)

    :ok
  end

  defp request(method, path, body \\ nil) do
    conn(method, path, if(body, do: Jason.encode!(body), else: nil))
    |> put_req_header("content-type", "application/json")
    |> DocumentOcrWeb.Endpoint.call([])
  end

  defp payload do
    %{
      "appId" => "test",
      "externalId" => "onboarding-1",
      "document" => %{"type" => "cnh", "country" => "BR"},
      "images" => [
        %{"side" => "front", "image" => Base.encode64("test/front.jpg")}
      ]
    }
  end

  defp create do
    conn = request(:post, "/v1/extractions", payload())
    assert conn.status == 202
    Jason.decode!(conn.resp_body)["id"]
  end

  defp drain do
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :preprocess)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :ocr)
    assert %{success: 3, failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)
  end

  defp job_args(id), do: id |> Documents.get_document!() |> Documents.job_args()

  test "HTTP creation, complete persisted pipeline and repeat execution" do
    id = create()
    [image] = Documents.get_document!(id).images
    assert image.blob_id
    assert {:ok, "test/front.jpg"} = AikeStorage.Blobs.get(image.blob)
    assert Documents.get_document!(id).status == "pending"
    pending = request(:get, "/v1/extractions/#{id}")
    assert pending.status == 200
    pending = Jason.decode!(pending.resp_body)
    assert pending["data"] == []
    assert pending["metadata"]["processingTimeMs"] == nil
    drain()
    document = Documents.get_document!(id)
    assert document.status == "completed"
    assert document.result.data["fields"]["full_name"]["value"] == "NARUTO UZUMAKI"
    assert document.result.data["fields"]["cpf"]["value"] == "52998224725"
    assert document.result.data["fields"]["birth_date"]["value"] == "1990-03-12"
    assert document.result.pipeline_version == "2026.11.0"

    for worker <- [
          Workers.PreprocessDocument,
          Workers.OcrDocument,
          Workers.ExtractFields,
          Workers.ValidateFields,
          Workers.CompleteDocument
        ] do
      assert :ok = perform_job(worker, job_args(id))
    end

    assert Repo.aggregate(DocumentResult, :count) == 1
    assert Repo.aggregate(DocumentArtifact, :count) == 3
    result = request(:get, "/v1/extractions/#{id}")
    assert result.status == 200
    assert Jason.decode!(result.resp_body)["status"] == "completed"
    show = request(:get, "/v1/extractions/#{id}") |> Map.fetch!(:resp_body) |> Jason.decode!()
    [%{"classification" => classification, "person" => person}] = show["data"]
    assert person["name"]["value"] == "NARUTO UZUMAKI"
    assert Map.keys(person) == ~w(birthdate name taxId)

    assert classification == %{
             "type" => "drivers_license",
             "subtype" => "printed",
             "country" => "BRA",
             "side" => "only_front"
           }
  end

  test "multipart upload persists blobs and returns the unified document result" do
    path = Path.join(System.tmp_dir!(), "aike-front-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "multipart-image")

    try do
      params = %{
        "appId" => "konoha",
        "externalId" => "multipart-1",
        "documentType" => "cnh",
        "country" => "BR",
        "imageFront" => %Plug.Upload{
          path: path,
          filename: "front.jpg",
          content_type: "image/jpeg"
        }
      }

      response =
        conn(:post, "/v1/extractions", params)
        |> DocumentOcrWeb.Endpoint.call([])

      assert response.status == 202
      id = Jason.decode!(response.resp_body)["id"]
      image = Documents.get_document!(id).images |> hd()
      assert image.blob_id
      assert image.blob.key =~ "kyc_documents/"

      drain()
      show = request(:get, "/v1/extractions/#{id}") |> Map.fetch!(:resp_body) |> Jason.decode!()
      assert show["status"] == "completed"
      assert hd(show["data"])["person"]["taxId"]["value"] == "52998224725"
    after
      File.rm(path)
    end
  end

  test "repeated bytes reuse an in-flight document and blob" do
    first = create()
    second = create()
    assert first == second
    assert Repo.aggregate(Document, :count) == 1
    assert Repo.aggregate(AikeStorage.Blob, :count) == 1

    assert hd(Documents.get_document!(first).images).blob_id ==
             hd(Documents.get_document!(second).images).blob_id
  end

  test "invalid multipart files are rejected before persistence" do
    path = Path.join(System.tmp_dir!(), "aike-empty-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    for file <- [
          "not a file",
          %Plug.Upload{path: path, filename: "empty.jpg", content_type: "image/jpeg"},
          %Plug.Upload{
            path: path <> ".missing",
            filename: "missing.jpg",
            content_type: "image/jpeg"
          }
        ] do
      params = %{
        "appId" => "test",
        "externalId" => "invalid-upload",
        "documentType" => "cnh",
        "country" => "BR",
        "imageFront" => file
      }

      assert conn(:post, "/v1/extractions", params)
             |> DocumentOcrWeb.Endpoint.call([])
             |> Map.fetch!(:status) == 422
    end

    assert Repo.aggregate(AikeStorage.Blob, :count) == 0
    assert Repo.aggregate(Document, :count) == 0
  end

  test "completed content returns the existing result without another document or OCR job" do
    id = create()
    drain()
    previous = Documents.get_document!(id)

    response = request(:post, "/v1/extractions", Map.put(payload(), "externalId", "new-request"))
    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["id"] == id
    assert body["runId"] == previous.run_id
    assert hd(body["data"])["person"]["taxId"]["value"] == "52998224725"
    assert Repo.aggregate(Document, :count) == 1
    assert Repo.aggregate(AikeStorage.Blob, :count) == 1
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
  end

  test "multipart reuses OCR from JSON regardless of filename or MIME metadata" do
    id = create()
    drain()
    path = Path.join(System.tmp_dir!(), "aike-reuse-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, "test/front.jpg")
    on_exit(fn -> File.rm(path) end)

    params = %{
      "appId" => "test",
      "externalId" => "multipart-reuse",
      "documentType" => "cnh",
      "country" => "BR",
      "imageFront" => %Plug.Upload{
        path: path,
        filename: "renamed.pdf",
        content_type: "application/pdf"
      }
    }

    response = conn(:post, "/v1/extractions", params) |> DocumentOcrWeb.Endpoint.call([])
    assert response.status == 200
    assert Jason.decode!(response.resp_body)["id"] == id
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
    assert Repo.aggregate(AikeStorage.Blob, :count) == 1
  end

  test "completed OCR is isolated by company and pipeline version" do
    id = create()
    drain()

    other_company =
      request(:post, "/v1/extractions", Map.put(payload(), "appId", "other-company"))

    assert other_company.status == 202
    refute Jason.decode!(other_company.resp_body)["id"] == id

    old_version = Application.fetch_env!(:document_ocr, :pipeline_version)
    on_exit(fn -> Application.put_env(:document_ocr, :pipeline_version, old_version) end)
    Application.put_env(:document_ocr, :pipeline_version, "changed-pipeline")
    changed = request(:post, "/v1/extractions", payload())
    assert changed.status == 202
    refute Jason.decode!(changed.resp_body)["id"] == id
  end

  test "completed content must match every image and its side" do
    images = [
      %{"side" => "front", "image" => Base.encode64("front-bytes")},
      %{"side" => "back", "image" => Base.encode64("back-bytes")}
    ]

    body = Map.put(payload(), "images", images)
    created = request(:post, "/v1/extractions", body)
    assert created.status == 202
    drain()
    reversed = request(:post, "/v1/extractions", Map.put(body, "images", Enum.reverse(images)))
    assert reversed.status == 200
    assert Jason.decode!(reversed.resp_body)["id"] == Jason.decode!(created.resp_body)["id"]

    for changed_images <- [
          [hd(images)],
          [hd(images), %{"side" => "back", "image" => Base.encode64("changed")}],
          Enum.map(
            images,
            &Map.update!(&1, "side", fn side -> if side == "front", do: "back", else: "front" end)
          )
        ] do
      assert request(:post, "/v1/extractions", Map.put(body, "images", changed_images)).status ==
               202
    end
  end

  test "failed documents do not satisfy content reuse" do
    id = create()
    assert {:ok, _} = Documents.cancel_document(id)
    response = request(:post, "/v1/extractions", payload())
    assert response.status == 202
    refute Jason.decode!(response.resp_body)["id"] == id
  end

  test "local uploads persist through OCR and reuploads restore missing file bytes" do
    original_root = Application.fetch_env!(:aike_storage, :local_root)

    root =
      Path.join(System.tmp_dir!(), "aike-pipeline-local-#{System.unique_integer([:positive])}")

    Application.put_env(:aike_storage, :adapter, AikeStorage.Adapter.Local)
    Application.put_env(:aike_storage, :local_root, root)

    on_exit(fn ->
      Application.put_env(:aike_storage, :local_root, original_root)
      File.rm_rf!(root)
    end)

    id = create()
    [image] = Documents.get_document!(id).images
    path = Path.join(root, image.blob.key)
    assert File.read!(path) == "test/front.jpg"
    File.rm!(path)

    assert {:ok, blob} =
             AikeStorage.Blobs.put(
               "test/front.jpg",
               "renamed.jpg",
               "image/jpeg",
               DocumentOcr.BlobOwner.owner()
             )

    assert blob.id == image.blob_id
    assert File.read!(path) == "test/front.jpg"
    drain()
    assert Documents.get_document!(id).status == "completed"
    assert request(:post, "/v1/extractions", payload()).status == 200
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
  end

  test "retrying a nonterminal stage doesn't duplicate downstream jobs" do
    id = create()
    assert :ok = perform_job(Workers.PreprocessDocument, job_args(id))
    assert :ok = perform_job(Workers.PreprocessDocument, job_args(id))
    assert length(all_enqueued(worker: Workers.OcrDocument)) == 1
    assert Repo.aggregate(DocumentArtifact, :count) == 1
  end

  test "explicit cancellation is terminal and queued work is cancelled" do
    id = create()
    response = request(:post, "/v1/extractions/#{id}/cancel")
    assert response.status == 200
    assert Jason.decode!(response.resp_body)["error"]["code"] == "cancelled"
    assert Documents.get_document!(id).status == "failed"

    assert {:cancel, :document_not_active} = perform_job(Workers.PreprocessDocument, job_args(id))
    assert request(:post, "/v1/extractions/#{id}/cancel").status == 409
  end

  test "idempotency key returns the original document without enqueueing a duplicate" do
    first =
      conn(:post, "/v1/extractions", Jason.encode!(payload()))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", "request-123")
      |> DocumentOcrWeb.Endpoint.call([])

    second =
      conn(:post, "/v1/extractions", Jason.encode!(payload()))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", "request-123")
      |> DocumentOcrWeb.Endpoint.call([])

    assert first.status == 202
    assert second.status == 202
    assert Jason.decode!(first.resp_body)["id"] == Jason.decode!(second.resp_body)["id"]
    assert Repo.aggregate(Document, :count) == 1
    assert Repo.aggregate(AikeStorage.Blob, :count) == 1
    assert length(all_enqueued(worker: Workers.PreprocessDocument)) == 1
  end

  test "storage retries then document fails" do
    id = create()
    Application.put_env(:aike_storage, :adapter, DocumentOcr.TestStorageFailure)
    assert %{failure: 1} = Oban.drain_queue(queue: :preprocess)
    assert Documents.get_document!(id).status == "processing"
    assert %{failure: 1} = Oban.drain_queue(queue: :preprocess, with_scheduled: true)
    assert %{discard: 1} = Oban.drain_queue(queue: :preprocess, with_scheduled: true)
    assert Documents.get_document!(id).status == "failed"
    assert Repo.aggregate(DocumentResult, :count) == 0
  end

  test "OCR failure remains processing until retry exhaustion" do
    Application.put_env(:document_ocr, :ocr_engine, DocumentOcr.TestOCRFailure)
    id = create()
    assert %{success: 1} = Oban.drain_queue(queue: :preprocess)
    assert %{failure: 1} = Oban.drain_queue(queue: :ocr)
    assert Documents.get_document!(id).status == "processing"
    assert %{failure: 1} = Oban.drain_queue(queue: :ocr, with_scheduled: true)
    assert %{discard: 1} = Oban.drain_queue(queue: :ocr, with_scheduled: true)
    assert Documents.get_document!(id).status == "failed"
  end

  test "invalid requests are atomic and unknown UUIDs return 404" do
    for body <- [
          %{},
          put_in(payload(), ["document", "type"], "unknown"),
          put_in(payload(), ["document", "type"], "rg"),
          Map.put(payload(), "externalId", ""),
          put_in(payload(), ["document", "country"], "US"),
          put_in(payload(), ["images"], []),
          put_in(payload(), ["images"], [
            %{"side" => "wrong", "image" => Base.encode64("x")}
          ])
        ] do
      assert request(:post, "/v1/extractions", body).status == 422
    end

    assert Repo.aggregate(Document, :count) == 0
    assert Repo.aggregate(AikeStorage.Blob, :count) == 0
    assert request(:get, "/v1/extractions/not-a-uuid").status == 422
    assert request(:get, "/v1/extractions/#{Ecto.UUID.generate()}").status == 404
  end

  test "invalid JSON uploads and storage references create no blobs or jobs" do
    for images <- [
          [%{"side" => "front", "source" => %{"type" => "object_storage", "key" => "x"}}],
          [%{"side" => "front", "image" => "invalid!"}],
          [%{"side" => "front", "image" => ""}],
          [%{"side" => "front", "image" => nil}],
          [%{"side" => "front", "image" => Base.encode64("bytes"), "filename" => 123}],
          List.duplicate(%{"side" => "front", "image" => Base.encode64("bytes")}, 2),
          [
            %{"side" => "front", "image" => Base.encode64("bytes")},
            %{"side" => "back", "image" => "invalid!"}
          ]
        ] do
      assert request(:post, "/v1/extractions", Map.put(payload(), "images", images)).status == 422
    end

    assert Repo.aggregate(AikeStorage.Blob, :count) == 0
    assert Repo.aggregate(Document, :count) == 0
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
  end

  test "document changeset rejects absent images and does not accept arbitrary status" do
    refute Document.changeset(%Document{}, %{}).valid?
    changeset = Document.changeset(%Document{}, %{status: "completed"})
    refute Map.has_key?(changeset.changes, :status)
  end

  test "validated rejection and low confidence drive final state" do
    for {value, confidence, status} <- [
          {"12345678900", 0.98, "rejected"},
          {"52998224725", 0.65, "requires_confirmation"}
        ] do
      response =
        request(
          :post,
          "/v1/extractions",
          put_in(payload(), ["images"], [%{"side" => "front", "image" => Base.encode64(value)}])
        )

      assert response.status == 202
      id = Jason.decode!(response.resp_body)["id"]
      assert %{success: 1} = Oban.drain_queue(queue: :preprocess)
      assert %{success: 1} = Oban.drain_queue(queue: :ocr)
      assert :ok = perform_job(Workers.ExtractFields, job_args(id))
      doc = Documents.get_document!(id)

      data =
        Documents.artifact(id, "extracted").data
        |> put_in(["fields", "cpf", "value"], value)
        |> put_in(["fields", "cpf", "confidence"], confidence)

      {:ok, _} = Documents.save_artifact(doc, "extracted", data)
      assert :ok = perform_job(Workers.ValidateFields, job_args(id))
      assert :ok = perform_job(Workers.CompleteDocument, job_args(id))
      assert Documents.get_document!(id).status == status
      assert request(:get, "/v1/extractions/#{id}").status == 200
    end
  end

  test "service authentication rejects absent and wrong tokens" do
    Application.put_env(:document_ocr, :service_token, "test-token")
    on_exit(fn -> Application.delete_env(:document_ocr, :service_token) end)
    assert request(:get, "/v1/extractions/missing").status == 401

    for {token, expected} <- [{"wrong", 401}, {"test-token", 422}] do
      response =
        conn(:get, "/v1/extractions/missing")
        |> put_req_header("authorization", "Bearer " <> token)
        |> DocumentOcrWeb.Endpoint.call([])

      assert response.status == expected
    end
  end

  test "stale processing structs cannot overwrite terminal state" do
    id = create()
    pending = Documents.get_document!(id)
    assert {:error, :invalid_transition} = DocumentOcr.Documents.Processor.complete(pending)
    {:ok, processing} = DocumentOcr.Documents.Processor.start_processing(pending)
    {:ok, completed} = DocumentOcr.Documents.Processor.complete(processing)

    assert {:error, :invalid_transition} =
             DocumentOcr.Documents.Processor.fail(processing, "late", "late")

    assert {:error, :invalid_transition} =
             DocumentOcr.Documents.Processor.start_processing(pending)

    assert {:ok, _} = DocumentOcr.Documents.Processor.complete(completed)
    assert Documents.get_document!(id).status == "completed"
  end

  test "jobs for deleted documents cancel without raising or enqueueing work" do
    id = create()
    args = job_args(id)
    Repo.delete!(Documents.get_document!(id))

    for worker <- [
          Workers.PreprocessDocument,
          Workers.OcrDocument,
          Workers.ExtractFields,
          Workers.ValidateFields,
          Workers.CompleteDocument
        ] do
      assert {:cancel, :document_not_found} = perform_job(worker, args)
    end

    assert all_enqueued(worker: Workers.OcrDocument) == []
  end

  test "two-sided input extracts the front regardless of upload order" do
    Application.put_env(:document_ocr, :storage, AikeStorage.Adapter.Fake)
    Application.put_env(:document_ocr, :ocr_engine, DocumentOcr.TestSideOCR)

    images =
      for side <- ["back", "front"] do
        %{"side" => side, "image" => Base.encode64(side <> ".jpg")}
      end

    response = request(:post, "/v1/extractions", Map.put(payload(), "images", images))
    assert response.status == 202
    id = Jason.decode!(response.resp_body)["id"]
    drain()
    result = Documents.get_document!(id).result.data
    assert result["fields"]["full_name"]["value"] == "FRONT PERSON"
    assert length(Documents.artifact(id, "raw_ocr").data["images"]) == 2
  end

  test "an RG is read from all its images and its fields come from the back" do
    original_extractors = Application.fetch_env!(:document_ocr, :extractors)
    Application.put_env(:document_ocr, :storage, AikeStorage.Adapter.Fake)
    Application.put_env(:document_ocr, :ocr_engine, DocumentOcr.TestRGOCR)

    Application.put_env(
      :document_ocr,
      :ocr_engines,
      Application.fetch_env!(:document_ocr, :ocr_engines) ++ [{DocumentOcr.TestRGOCR, "fake-1"}]
    )

    Application.put_env(
      :document_ocr,
      :extractors,
      Map.put(original_extractors, {"rg", "fake-cnh-1"}, DocumentOcr.Extraction.RGLabels)
    )

    on_exit(fn -> Application.put_env(:document_ocr, :extractors, original_extractors) end)

    images =
      for side <- ["front", "back"] do
        %{"side" => side, "image" => Base.encode64(side <> ".jpg")}
      end

    body =
      payload()
      |> put_in(["document", "type"], "id_card")
      |> Map.put("images", images)

    response = request(:post, "/v1/extractions", body)
    assert response.status == 202
    id = Jason.decode!(response.resp_body)["id"]
    drain()

    document = Documents.get_document!(id)
    assert document.document_type == "rg"
    assert document.status == "completed"

    assert %{
             "full_name" => %{"value" => "NARUTO UZUMAKI"},
             "rg_number" => %{"value" => "123456789"},
             "birth_date" => %{"value" => "1990-03-12"},
             "cpf" => %{"value" => "52998224725"}
           } = document.result.data["fields"]
  end

  defp with_rg_engine do
    original_extractors = Application.fetch_env!(:document_ocr, :extractors)
    Application.put_env(:document_ocr, :storage, AikeStorage.Adapter.Fake)
    Application.put_env(:document_ocr, :ocr_engine, DocumentOcr.TestRGOCR)

    Application.put_env(
      :document_ocr,
      :ocr_engines,
      Application.fetch_env!(:document_ocr, :ocr_engines) ++ [{DocumentOcr.TestRGOCR, "fake-1"}]
    )

    Application.put_env(
      :document_ocr,
      :extractors,
      Map.put(original_extractors, {"rg", "fake-cnh-1"}, DocumentOcr.Extraction.RGLabels)
    )

    on_exit(fn -> Application.put_env(:document_ocr, :extractors, original_extractors) end)
  end

  test "repeating a request without externalId under the same idempotency key returns the same extraction" do
    path = Path.join(System.tmp_dir!(), "aike-idem-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "test/front.jpg")
    on_exit(fn -> File.rm(path) end)

    send_once = fn ->
      file = %Plug.Upload{path: path, filename: "document.jpg", content_type: "image/jpeg"}

      conn(:post, "/v1/extractions", %{"appId" => "test", "documentType" => "cnh", "file" => file})
      |> put_req_header("idempotency-key", "konoha-retry-1")
      |> DocumentOcrWeb.Endpoint.call([])
    end

    first = send_once.()
    second = send_once.()
    assert first.status == 202
    assert second.status in [200, 202]
    assert Jason.decode!(second.resp_body)["id"] == Jason.decode!(first.resp_body)["id"]
  end

  defp upload_only_file(content) do
    path = Path.join(System.tmp_dir!(), "aike-file-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    file = %Plug.Upload{path: path, filename: "document.jpg", content_type: "image/jpeg"}

    conn(:post, "/v1/extractions", %{"appId" => "test", "file" => file})
    |> DocumentOcrWeb.Endpoint.call([])
  end

  defp drain_all do
    Oban.drain_queue(queue: :preprocess)
    Oban.drain_queue(queue: :ocr)
    Oban.drain_queue(queue: :default, with_recursion: true)
  end

  test "only the file is needed: the type is detected and the country defaults to BR" do
    with_rg_engine()
    response = upload_only_file("back.jpg")
    assert response.status == 202
    id = Jason.decode!(response.resp_body)["id"]

    document = Documents.get_document!(id)
    assert {document.document_type, document.country} == {"auto", "BR"}
    assert {:ok, _} = Ecto.UUID.cast(document.external_id)
    assert hd(document.images).side == "single"

    drain_all()
    show = request(:get, "/v1/extractions/#{id}") |> Map.fetch!(:resp_body) |> Jason.decode!()
    assert show["status"] == "completed"
    assert Map.keys(show) == ~w(data error id metadata runId status version)
    assert {show["id"], show["version"], show["error"]} == {id, "v1", nil}

    assert [%{"classification" => classification, "person" => person, "document" => fields}] =
             show["data"]

    assert classification == %{
             "type" => "id_card",
             "subtype" => "printed",
             "country" => "BRA",
             "side" => "front_and_back"
           }

    assert fields["number"]["value"] == "123456789"
    assert person["name"]["value"] == "NARUTO UZUMAKI"

    assert Map.keys(person["name"]) == ~w(confidence rawValue status value)

    assert [%{"side" => "single", "mimetype" => _, "size" => _, "sha256" => _}] =
             show["metadata"]["filesInfo"]

    assert is_integer(show["metadata"]["processingTimeMs"])
  end

  test "an automatic type that matches no document ends as failed with a reason" do
    with_rg_engine()
    response = upload_only_file("front.jpg")
    assert response.status == 202
    id = Jason.decode!(response.resp_body)["id"]

    drain_all()
    document = Documents.get_document!(id)
    assert document.status == "failed"
    assert document.error_code == "unrecognized_document"
  end

  test "a request without a document names the missing file" do
    response =
      conn(:post, "/v1/extractions", %{"externalId" => "x"}) |> DocumentOcrWeb.Endpoint.call([])

    assert response.status == 422
    assert [%{"field" => "file"}] = Jason.decode!(response.resp_body)["errors"]
  end

  test "an RG is refused when the active configuration has no RG extractor" do
    body = put_in(payload(), ["document", "type"], "rg")
    assert request(:post, "/v1/extractions", body).status == 422
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
  end

  test "OCR authentication fails closed and precedes JSON parsing" do
    on_exit(fn ->
      Application.delete_env(:document_ocr, :service_token)
      Application.delete_env(:document_ocr, :auth_required)
    end)

    Application.put_env(:document_ocr, :service_token, "")
    conn = conn(:get, "/v1/extractions/missing") |> put_req_header("authorization", "Bearer ")
    assert DocumentOcrWeb.Endpoint.call(conn, []).status == 401
    Application.delete_env(:document_ocr, :service_token)
    Application.put_env(:document_ocr, :auth_required, true)

    conn =
      conn(:post, "/v1/extractions", "{") |> put_req_header("content-type", "application/json")

    assert DocumentOcrWeb.Endpoint.call(conn, []).status == 401
  end
end
