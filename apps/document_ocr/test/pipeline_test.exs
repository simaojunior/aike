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

    Application.put_env(
      :document_ocr,
      :ocr_engines,
      original_engines ++
        [{DocumentOcr.TestOCRFailure, "fake-1"}, {DocumentOcr.TestSideOCR, "fake-1"}]
    )

    on_exit(fn ->
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
      "app_id" => "test",
      "external_id" => "onboarding-1",
      "document" => %{"type" => "cnh", "country" => "BR"},
      "images" => [
        %{"side" => "front", "source" => %{"type" => "object_storage", "key" => "test/front.jpg"}}
      ]
    }
  end

  defp create do
    conn = request(:post, "/v1/documents", payload())
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
    assert Documents.get_document!(id).status == "pending"
    pending = request(:get, "/v1/documents/#{id}")
    assert pending.status == 200
    assert Jason.decode!(pending.resp_body)["result"] == nil
    drain()
    document = Documents.get_document!(id)
    assert document.status == "completed"
    assert document.result.data["person"]["full_name"]["value"] == "MARIA DA SILVA"
    assert document.result.data["person"]["cpf"]["value"] == "52998224725"
    assert document.result.data["person"]["birth_date"]["value"] == "1990-03-12"
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
    result = request(:get, "/v1/documents/#{id}")
    assert result.status == 200
    assert Jason.decode!(result.resp_body)["status"] == "completed"
    show = request(:get, "/v1/documents/#{id}") |> Map.fetch!(:resp_body) |> Jason.decode!()
    assert show["result"]["person"]["fullName"]["value"] == "MARIA DA SILVA"
  end

  test "multipart upload persists blobs and returns the unified document result" do
    path = Path.join(System.tmp_dir!(), "aike-front-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "multipart-image")

    try do
      params = %{
        "app_id" => "acme",
        "external_id" => "multipart-1",
        "document_type" => "cnh",
        "country" => "BR",
        "image_front" => %Plug.Upload{
          path: path,
          filename: "front.jpg",
          content_type: "image/jpeg"
        }
      }

      response =
        conn(:post, "/v1/documents")
        |> DocumentOcrWeb.DocumentController.create(params)

      assert response.status == 202
      id = Jason.decode!(response.resp_body)["id"]
      image = Documents.get_document!(id).images |> hd()
      assert image.blob_id
      assert image.blob.key =~ "kyc_documents/"

      drain()
      show = request(:get, "/v1/documents/#{id}") |> Map.fetch!(:resp_body) |> Jason.decode!()
      assert show["status"] == "completed"
      assert show["result"]["person"]["cpf"]["value"] == "52998224725"
    after
      File.rm(path)
    end
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
    response = request(:post, "/v1/documents/#{id}/cancel")
    assert response.status == 200
    assert Jason.decode!(response.resp_body)["errorCode"] == "cancelled"
    assert Documents.get_document!(id).status == "failed"

    assert {:cancel, :document_not_active} = perform_job(Workers.PreprocessDocument, job_args(id))
    assert request(:post, "/v1/documents/#{id}/cancel").status == 409
  end

  test "idempotency key returns the original document without enqueueing a duplicate" do
    first =
      conn(:post, "/v1/documents", Jason.encode!(payload()))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", "request-123")
      |> DocumentOcrWeb.Endpoint.call([])

    second =
      conn(:post, "/v1/documents", Jason.encode!(payload()))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", "request-123")
      |> DocumentOcrWeb.Endpoint.call([])

    assert first.status == 202
    assert second.status == 202
    assert Jason.decode!(first.resp_body)["id"] == Jason.decode!(second.resp_body)["id"]
    assert Repo.aggregate(Document, :count) == 1
    assert length(all_enqueued(worker: Workers.PreprocessDocument)) == 1
  end

  test "storage retries then document fails" do
    id = create()
    Application.put_env(:document_ocr, :storage, DocumentOcr.TestStorageFailure)
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
          put_in(payload(), ["document", "country"], "US"),
          put_in(payload(), ["images"], []),
          put_in(payload(), ["images"], [
            %{"side" => "wrong", "source" => %{"type" => "object_storage", "key" => "x"}}
          ])
        ] do
      assert request(:post, "/v1/documents", body).status == 422
    end

    assert Repo.aggregate(Document, :count) == 0
    assert request(:get, "/v1/documents/not-a-uuid").status == 404
    assert request(:get, "/v1/documents/#{Ecto.UUID.generate()}").status == 404
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
      id = create()
      assert %{success: 1} = Oban.drain_queue(queue: :preprocess)
      assert %{success: 1} = Oban.drain_queue(queue: :ocr)
      assert :ok = perform_job(Workers.ExtractFields, job_args(id))
      doc = Documents.get_document!(id)

      data =
        Documents.artifact(id, "extracted").data
        |> put_in(["person", "cpf", "value"], value)
        |> put_in(["person", "cpf", "confidence"], confidence)

      {:ok, _} = Documents.save_artifact(doc, "extracted", data)
      assert :ok = perform_job(Workers.ValidateFields, job_args(id))
      assert :ok = perform_job(Workers.CompleteDocument, job_args(id))
      assert Documents.get_document!(id).status == status
      assert request(:get, "/v1/documents/#{id}").status == 200
    end
  end

  test "service authentication rejects absent and wrong tokens" do
    Application.put_env(:document_ocr, :service_token, "test-token")
    on_exit(fn -> Application.delete_env(:document_ocr, :service_token) end)
    assert request(:get, "/v1/documents/missing").status == 401

    for {token, expected} <- [{"wrong", 401}, {"test-token", 404}] do
      response =
        conn(:get, "/v1/documents/missing")
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
    Application.put_env(:document_ocr, :storage, DocumentOcr.TestSideStorage)
    Application.put_env(:document_ocr, :ocr_engine, DocumentOcr.TestSideOCR)

    images =
      for side <- ["back", "front"] do
        %{"side" => side, "source" => %{"type" => "object_storage", "key" => side <> ".jpg"}}
      end

    response = request(:post, "/v1/documents", Map.put(payload(), "images", images))
    assert response.status == 202
    id = Jason.decode!(response.resp_body)["id"]
    drain()
    result = Documents.get_document!(id).result.data
    assert result["person"]["full_name"]["value"] == "FRONT PERSON"
    assert length(Documents.artifact(id, "raw_ocr").data["images"]) == 2
  end

  test "domain creation rejects RG until an extractor is available" do
    attrs = %{
      app_id: "test",
      external_id: "rg",
      document_type: "rg",
      country: "BR",
      pipeline_version: "test",
      request_id: "test",
      images: [%{side: "front", source_key: "rg.jpg"}]
    }

    assert {:error, :document, changeset, _} = Documents.create_document(attrs)
    assert Keyword.has_key?(changeset.errors, :document_type)
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
  end

  test "OCR authentication fails closed and precedes JSON parsing" do
    on_exit(fn ->
      Application.delete_env(:document_ocr, :service_token)
      Application.delete_env(:document_ocr, :auth_required)
    end)

    Application.put_env(:document_ocr, :service_token, "")
    conn = conn(:get, "/v1/documents/missing") |> put_req_header("authorization", "Bearer ")
    assert DocumentOcrWeb.Endpoint.call(conn, []).status == 401
    Application.delete_env(:document_ocr, :service_token)
    Application.put_env(:document_ocr, :auth_required, true)
    conn = conn(:post, "/v1/documents", "{") |> put_req_header("content-type", "application/json")
    assert DocumentOcrWeb.Endpoint.call(conn, []).status == 401
  end
end
