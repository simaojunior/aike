defmodule DocumentOcr.ReprocessingTestEngine do
  @behaviour DocumentOcr.OCR.Engine
  alias DocumentOcr.OCR.Fake

  def extract(bytes, opts) do
    {:ok, raw} = Fake.extract(bytes, opts)
    [name | rest] = raw["text"]
    {:ok, %{"text" => [%{name | "text" => "SASUKE UCHIHA"} | rest]}}
  end
end

defmodule DocumentOcr.ReprocessingTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: DocumentOcr.Repo
  import Plug.Test
  import Plug.Conn
  import Ecto.Query
  alias DocumentOcr.{Documents, Repo}
  alias DocumentOcr.Documents.{DocumentArtifact, DocumentResult, Processor}
  alias DocumentOcr.Extraction.CNH
  alias DocumentOcr.OCR.Fake
  alias DocumentOcr.Workers
  alias Ecto.Adapters.SQL.Sandbox

  @workers [
    Workers.PreprocessDocument,
    Workers.OcrDocument,
    Workers.ExtractFields,
    Workers.ValidateFields,
    Workers.CompleteDocument
  ]

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    keys = [:ocr_engine, :ocr_engine_version, :ocr_engines, :pipeline_version]
    original = Map.new(keys, &{&1, Application.fetch_env!(:document_ocr, &1)})

    on_exit(fn ->
      Enum.each(original, fn {key, value} -> Application.put_env(:document_ocr, key, value) end)
    end)

    :ok
  end

  defp create do
    {:ok, %{document: document}} =
      Documents.create_document(%{
        app_id: "test",
        external_id: "reprocess",
        document_type: "cnh",
        country: "BR",
        request_id: "original-request",
        images: [%{side: "front", source_key: "fake.jpg"}]
      })

    document
  end

  defp drain do
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :preprocess)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :ocr)
    assert %{success: 3, failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)
  end

  defp request(method, path, body \\ nil) do
    conn(method, path, if(body, do: Jason.encode!(body), else: nil))
    |> put_req_header("content-type", "application/json")
    |> DocumentOcrWeb.Endpoint.call([])
  end

  test "HTTP reprocess creates a new run, clears old output and completes with requested configuration" do
    original = create()
    drain()
    old_result = Documents.get_document!(original.id).result
    old_images = Documents.get_document!(original.id).images
    Application.put_env(:document_ocr, :ocr_engine, DocumentOcr.ReprocessingTestEngine)
    Application.put_env(:document_ocr, :ocr_engine_version, "reprocess-1")

    Application.put_env(:document_ocr, :ocr_engines, [
      {DocumentOcr.ReprocessingTestEngine, "reprocess-1"}
    ])

    Application.put_env(:document_ocr, :pipeline_version, "2026.12.0")

    response =
      request(:post, "/v1/extractions/#{original.id}/reprocess", %{pipelineVersion: "2026.12.0"})

    assert response.status == 202
    current = Documents.get_document!(original.id)

    assert %{"id" => id, "runId" => run_id, "status" => "pending", "data" => data} =
             Jason.decode!(response.resp_body)

    assert {id, run_id, data} == {original.id, current.run_id, []}

    assert current.run_id != original.run_id
    assert current.request_id != original.request_id
    assert current.pipeline_version == "2026.12.0"
    assert current.images == old_images
    assert current.result == nil
    assert Repo.aggregate(DocumentArtifact, :count) == 0
    assert request(:get, "/v1/extractions/#{original.id}").status == 200

    for worker <- @workers do
      assert {:cancel, :stale_run} = perform_job(worker, Documents.job_args(original))
    end

    drain()
    document = Documents.get_document!(original.id)
    assert document.status == "completed"
    assert document.result.id != old_result.id
    assert document.result.run_id == current.run_id
    assert document.result.pipeline_version == "2026.12.0"
    assert document.result.ocr_engine_version == "reprocess-1"
    assert document.result.data["fields"]["full_name"]["value"] == "SASUKE UCHIHA"
    assert Repo.aggregate(DocumentResult, :count) == 1
    assert Repo.aggregate(DocumentArtifact, :count) == 3

    assert Repo.all(from(a in DocumentArtifact, select: a.run_id)) |> Enum.uniq() == [
             current.run_id
           ]

    response = request(:get, "/v1/extractions/#{original.id}")
    assert response.status == 200
    assert Jason.decode!(response.resp_body)["runId"] == current.run_id

    assert Jason.decode!(request(:get, "/v1/extractions/#{original.id}").resp_body)["runId"] ==
             current.run_id

    for worker <- @workers do
      assert {:cancel, :stale_run} = perform_job(worker, Documents.job_args(original))
    end

    assert Documents.get_document!(original.id).result == document.result
  end

  test "stale structs cannot change status, artifacts or result after restart" do
    original = create()
    {:ok, raw} = Fake.extract("bytes", [])
    {:ok, data} = CNH.extract(raw)
    data = DocumentOcr.Validation.validate_result(data)
    {:ok, current} = Documents.reprocess_document(original.id, "2026.11.0")
    assert {:error, :stale_run} = Processor.start_processing(original)
    assert {:error, :stale_run} = Processor.complete(original)
    assert {:error, :stale_run} = Processor.fail(original, "old", "old failure")
    assert {:error, :stale_run} = Documents.save_artifact(original, "raw_ocr", %{})
    assert {:error, :stale_run} = Documents.save_result(original, data)
    assert Documents.get_document!(current.id).status == "pending"
    assert Repo.aggregate(DocumentResult, :count) == 0
    assert Repo.aggregate(DocumentArtifact, :count) == 0
  end

  test "queued, retried, final-attempt and legacy jobs cannot join the new execution" do
    original = create()
    assert %{success: 1} = Oban.drain_queue(queue: :preprocess)
    {:ok, current} = Documents.reprocess_document(original.id, "2026.11.0")

    assert {:cancel, :stale_run} =
             perform_job(Workers.PreprocessDocument, %{document_id: original.id})

    assert {:cancel, :stale_run} =
             Workers.OcrDocument.perform(%Oban.Job{
               args: %{"document_id" => original.id, "run_id" => original.run_id},
               attempt: 3,
               max_attempts: 3
             })

    assert %{cancelled: 1, success: 0, failure: 0} = Oban.drain_queue(queue: :ocr)
    assert Documents.get_document!(current.id).status == "pending"
    drain()
    assert Documents.get_document!(current.id).status == "completed"
  end

  test "reprocessing failed or legacy documents clears errors and captures new configuration" do
    document = create()
    {:ok, processing} = Processor.start_processing(document)
    {:ok, failed} = Processor.fail(processing, "processing_failed", "failure")

    failed
    |> Ecto.Changeset.change(ocr_engine: nil, ocr_engine_version: nil, extractor_version: nil)
    |> Repo.update!()

    {:ok, current} = Documents.reprocess_document(document.id, "2026.11.0")
    assert current.status == "pending"
    assert current.error_code == nil
    assert current.error_message == nil
    assert current.ocr_engine == "DocumentOcr.OCR.Fake"
    assert current.run_id != failed.run_id
  end

  test "bad requests and unsupported configuration leave the existing run intact" do
    document = create()
    drain()
    original = Documents.get_document!(document.id)

    for body <- [
          %{},
          %{pipelineVersion: nil},
          %{pipelineVersion: ""},
          %{pipelineVersion: "unknown"},
          %{pipelineVersion: 12}
        ] do
      assert request(:post, "/v1/extractions/#{document.id}/reprocess", body).status == 422
    end

    assert request(:post, "/v1/extractions/not-a-uuid/reprocess", %{pipelineVersion: "2026.11.0"}).status ==
             422

    assert request(:post, "/v1/extractions/#{Ecto.UUID.generate()}/reprocess", %{
             pipelineVersion: "2026.11.0"
           }).status == 404

    Application.put_env(:document_ocr, :ocr_engine_version, "missing")

    assert request(:post, "/v1/extractions/#{document.id}/reprocess", %{
             pipelineVersion: "2026.11.0"
           }).status == 503

    assert Documents.get_document!(document.id) == original
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
  end

  test "outer rollback restores the old run, outputs and jobs atomically" do
    document = create()
    drain()
    before_restart = Documents.get_document!(document.id)
    # An outer transaction models failure after the whole context operation.
    # Its rollback must restore the previous run, outputs and enqueue atomically.
    assert {:error, :abort} =
             Repo.transaction(fn ->
               assert {:ok, _} = Documents.reprocess_document(document.id, "2026.11.0")
               Repo.rollback(:abort)
             end)

    assert Documents.get_document!(document.id) == before_restart
    assert Repo.aggregate(DocumentArtifact, :count) == 3
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
  end

  test "database rejects artifacts belonging to another run" do
    document = create()

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%DocumentArtifact{
        document_id: document.id,
        run_id: Ecto.UUID.generate(),
        kind: "invalid",
        data: %{}
      })
    end
  end

  test "enqueue database failure rolls back reset and output deletion" do
    document = create()
    drain()
    original = Documents.get_document!(document.id)
    # This transaction-local constraint targets only this generated fixture ID.
    Repo.query!(
      "ALTER TABLE oban_jobs ADD CONSTRAINT kyc_test_enqueue_failure CHECK (args->>'document_id' <> '#{document.id}') NOT VALID"
    )

    assert_raise Ecto.ConstraintError, fn ->
      Documents.reprocess_document(document.id, "2026.11.0")
    end

    assert Documents.get_document!(document.id) == original
    assert Repo.aggregate(DocumentArtifact, :count) == 3
    assert all_enqueued(worker: Workers.PreprocessDocument) == []
  end
end
