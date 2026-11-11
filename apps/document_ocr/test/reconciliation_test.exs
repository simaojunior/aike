defmodule DocumentOcr.ReconciliationTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: DocumentOcr.Repo
  import Ecto.Query
  alias DocumentOcr.{Documents, Reconciliation, Repo}
  alias DocumentOcr.Documents.Processor
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp create do
    {:ok, %{document: document, job: job}} =
      Documents.create_document(%{
        app_id: "test",
        external_id: "reconcile",
        document_type: "cnh",
        country: "BR",
        request_id: "request",
        images: [%{side: "front", source_key: "fake.jpg"}]
      })

    {document, job}
  end

  defp discard(job) do
    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
      set: [state: "discarded", attempt: 3, discarded_at: DateTime.utc_now()]
    )
  end

  test "repairs pending and processing documents after exhausted jobs, idempotently" do
    for status <- [:pending, :processing] do
      {document, job} = create()
      if status == :processing, do: Processor.start_processing(document)
      discard(job)
      assert {:ok, 1} = Reconciliation.run()
      repaired = Documents.get_document!(document.id)
      assert repaired.status == "failed"
      assert repaired.error_code == "processing_exhausted"
      assert repaired.run_id == document.run_id
      assert {:ok, 0} = Reconciliation.run()
    end
  end

  test "an old nonterminal record with no remaining job becomes failed" do
    {document, job} = create()
    Repo.delete!(job)

    Repo.update_all(from(d in DocumentOcr.Documents.Document, where: d.id == ^document.id),
      set: [updated_at: DateTime.add(DateTime.utc_now(), -7200)]
    )

    assert {:ok, 1} = Reconciliation.run()
    assert Documents.get_document!(document.id).status == "failed"
    assert {:ok, 0} = Reconciliation.run()
  end

  test "available, executing, retryable or scheduled work prevents repair" do
    for state <- ~w(available executing retryable scheduled) do
      {document, job} = create()
      discard(job)

      Repo.insert!(%Oban.Job{
        worker: "DocumentOcr.Workers.OcrDocument",
        queue: "ocr",
        args: Documents.job_args(document),
        state: state
      })

      assert {:ok, :skipped} = Reconciliation.reconcile(document.id, document.run_id)
      assert Documents.get_document!(document.id).status == "pending"
    end

    assert {:ok, 0} = Reconciliation.run()
  end

  test "old runs cannot fail a new reprocessing run, even after selection" do
    {document, job} = create()
    discard(job)
    {:ok, current} = Documents.reprocess_document(document.id, document.pipeline_version)
    assert {:ok, :skipped} = Reconciliation.reconcile(document.id, document.run_id)
    assert {:ok, 0} = Reconciliation.run()
    assert Documents.get_document!(document.id).run_id == current.run_id
    assert Documents.get_document!(document.id).status == "pending"
  end

  test "terminal states remain unchanged" do
    for finish <- [
          &Processor.complete/1,
          &Processor.reject/1,
          &Processor.require_confirmation(&1, "review"),
          &Processor.cancel/1
        ] do
      {document, job} = create()
      {:ok, processing} = Processor.start_processing(document)
      {:ok, terminal} = finish.(processing)
      discard(job)
      assert {:ok, :skipped} = Reconciliation.reconcile(document.id, document.run_id)
      assert Documents.get_document!(document.id).status == terminal.status
    end

    assert {:ok, 0} = Reconciliation.run()
  end

  test "missing discarded evidence and unrelated workers cannot trigger repair" do
    {document, job} = create()
    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "completed"])

    Repo.insert!(%Oban.Job{
      worker: "Other.Worker",
      queue: "default",
      args: Documents.job_args(document),
      state: "discarded"
    })

    assert {:ok, :skipped} = Reconciliation.reconcile(document.id, document.run_id)
    assert {:ok, 0} = Reconciliation.run()
  end

  test "bounded batches continue from repaired documents" do
    for _ <- 1..3 do
      {_document, job} = create()
      discard(job)
    end

    assert {:ok, 2} = Reconciliation.run(2)
    assert {:ok, 1} = Reconciliation.run(2)
    assert {:ok, 0} = Reconciliation.run(2)
  end

  test "maintenance worker repairs exhausted processing without rerunning OCR" do
    {document, job} = create()
    discard(job)
    assert :ok = perform_job(DocumentOcr.Workers.ReconcileDocuments, %{})
    assert Documents.get_document!(document.id).status == "failed"
    assert all_enqueued(worker: DocumentOcr.Workers.OcrDocument) == []
  end
end
