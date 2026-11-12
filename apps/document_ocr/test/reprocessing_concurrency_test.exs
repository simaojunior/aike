defmodule DocumentOcr.BlockingRunTestStorage do
  @behaviour DocumentOcr.Storage
  def get(_) do
    send(Application.fetch_env!(:document_ocr, :run_test_owner), {:storage_waiting, self()})

    receive do
      {:release_storage, :success} -> {:ok, "fake-image-data"}
      {:release_storage, :failure} -> {:error, :storage_failed}
    after
      10_000 -> {:error, :test_timeout}
    end
  end
end

defmodule DocumentOcr.ReprocessingConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias DocumentOcr.{Documents, Repo, Workers}
  alias DocumentOcr.Documents.{Document, DocumentArtifact, DocumentResult}
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    # Real independent PostgreSQL connections: a shared sandbox connection cannot
    # exercise competing row locks. These fixture rows are explicitly cleaned up.
    Sandbox.mode(Repo, :manual)
    storage = Application.fetch_env!(:document_ocr, :storage)
    Application.put_env(:document_ocr, :storage, DocumentOcr.BlockingRunTestStorage)
    Application.put_env(:document_ocr, :run_test_owner, self())

    document =
      unboxed(fn ->
        {:ok, %{document: document}} =
          Documents.create_document(%{
            app_id: "concurrency-test",
            external_id: Ecto.UUID.generate(),
            request_id: "concurrency-test",
            document_type: "cnh",
            country: "BR",
            images: [%{side: "front", source_key: "fake.jpg"}]
          })

        document
      end)

    on_exit(fn ->
      Application.put_env(:document_ocr, :storage, storage)
      Application.delete_env(:document_ocr, :run_test_owner)

      unboxed(fn ->
        Repo.delete_all(from(j in Oban.Job, where: j.args["document_id"] == ^document.id))
        Repo.delete_all(from(d in Document, where: d.id == ^document.id))
      end)
    end)

    %{document: document}
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)
  defp backend_pid, do: Repo.query!("SELECT pg_backend_pid()").rows |> hd() |> hd()

  defp job(document),
    do: %Oban.Job{
      args: %{"document_id" => document.id, "run_id" => document.run_id},
      attempt: 3,
      max_attempts: 3
    }

  defp race(document, outcome) do
    owner = self()

    worker =
      Task.async(fn ->
        unboxed(fn ->
          send(owner, {:worker_connection, backend_pid()})
          Workers.PreprocessDocument.perform(job(document))
        end)
      end)

    assert_receive {:worker_connection, worker_backend}, 2000
    assert_receive {:storage_waiting, worker_pid}, 2000

    restart =
      Task.async(fn ->
        unboxed(fn ->
          send(owner, {:restart_connection, backend_pid()})
          Documents.reprocess_document(document.id, "2026.11.0")
        end)
      end)

    try do
      assert_receive {:restart_connection, restart_backend}, 2000
      refute worker_backend == restart_backend

      refute unboxed(fn ->
               Repo.query!("SELECT $1::integer = ANY(pg_blocking_pids($2::integer))", [
                 worker_backend,
                 restart_backend
               ]).rows == [[true]]
             end)

      assert {:ok, restarted} = Task.await(restart, 5000)
      assert restarted.run_id != document.run_id
      send(worker_pid, {:release_storage, outcome})
      result = Task.await(worker, 5000)

      unboxed(fn ->
        current = Documents.get_document!(document.id)
        assert current.run_id == restarted.run_id
        assert current.status == "pending"
        assert current.error_code == nil
        assert current.result == nil
        assert Repo.all(from(a in DocumentArtifact, where: a.document_id == ^document.id)) == []
        assert Repo.all(from(r in DocumentResult, where: r.document_id == ^document.id)) == []
        assert {:cancel, :stale_run} = Workers.OcrDocument.perform(job(document))
        assert {:cancel, :stale_run} = Workers.CompleteDocument.perform(job(document))
      end)

      result
    after
      if Process.alive?(worker.pid), do: Task.shutdown(worker, :brutal_kill)
      if Process.alive?(restart.pid), do: Task.shutdown(restart, :brutal_kill)
    end
  end

  test "restart waits for an in-flight stage then removes its old artifact", %{document: document} do
    assert {:cancel, :stale_run} = race(document, :success)
  end

  test "old final-attempt failure cannot fail a run created while it was executing", %{
    document: document
  } do
    assert {:cancel, :stale_run} = race(document, :failure)
  end

  test "simultaneous reprocess calls serialize and only the latest run remains current", %{
    document: document
  } do
    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          receive do
            :start -> unboxed(fn -> Documents.reprocess_document(document.id, "2026.11.0") end)
          end
        end)
      end

    try do
      Enum.each(tasks, &send(&1.pid, :start))

      runs =
        Enum.map(tasks, fn task ->
          assert {:ok, run} = Task.await(task, 5000)
          run
        end)

      assert runs |> Enum.map(& &1.run_id) |> Enum.uniq() |> length() == 2

      unboxed(fn ->
        current = Documents.get_document!(document.id)
        assert current.run_id in Enum.map(runs, & &1.run_id)
        stale = Enum.find(runs, &(&1.run_id != current.run_id))
        assert {:cancel, :stale_run} = Workers.PreprocessDocument.perform(job(stale))
        assert current.status == "pending"
      end)
    after
      for task <- tasks, Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
    end
  end
end
