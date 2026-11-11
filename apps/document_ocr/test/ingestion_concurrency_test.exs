defmodule DocumentOcr.IngestionConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias AikeStorage.Adapter.Local
  alias AikeStorage.{Blob, Ingestion, Reconciliation}
  alias DocumentOcr.{Documents, Repo}
  alias DocumentOcr.Documents.Document
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    root = Path.join(System.tmp_dir!(), "aike-crash-#{Ecto.UUID.generate()}")
    previous = Application.get_all_env(:aike_storage)
    Application.put_env(:aike_storage, :local_root, root)
    Application.put_env(:aike_storage, :adapter, Local)
    tenant = Ecto.UUID.generate()

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from(j in Oban.Job, where: j.args["safety_tenant"] == ^tenant))
        ids = Repo.all(from(d in Document, where: d.app_id == ^tenant, select: d.id))

        for id <- ids,
            do: Repo.delete_all(from(j in Oban.Job, where: j.args["document_id"] == ^id))

        Repo.delete_all(from(d in Document, where: d.app_id == ^tenant))

        hashes =
          Enum.map([tenant <> "-upload", tenant <> "-crash"], &:crypto.hash(:sha256, &1))
          |> Enum.map(&Base.encode16(&1, case: :lower))

        Repo.delete_all(from(b in Blob, where: b.sha256 in ^hashes))
      end)

      Enum.each(previous, fn {key, value} -> Application.put_env(:aike_storage, key, value) end)
      File.rm_rf!(root)
    end)

    %{tenant: tenant}
  end

  test "concurrent identical uploads commit one parent, one blob and one initial job", %{
    tenant: tenant
  } do
    attrs = %{
      app_id: tenant,
      external_id: "same",
      country: "BR",
      document_type: "cnh",
      request_id: tenant,
      idempotency_key: "same-key"
    }

    upload = %{
      side: "front",
      binary: tenant <> "-upload",
      filename: "front.jpg",
      mime_type: "image/jpeg"
    }

    tasks =
      for _ <- 1..2,
          do:
            Task.async(fn ->
              Sandbox.unboxed_run(Repo, fn ->
                Documents.create_document_from_uploads(attrs, [upload])
              end)
            end)

    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert [{:ok, first}, {:ok, second}] = results
    assert first.document.id == second.document.id

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(from(d in Document, where: d.app_id == ^tenant), :count) == 1

      assert Repo.aggregate(
               from(j in Oban.Job, where: j.args["document_id"] == ^first.document.id),
               :count
             ) == 1
    end)
  end

  test "killing ingestion rolls back SQL; reconciliation recovers bytes left before ownership", %{
    tenant: tenant
  } do
    parent = self()
    upload = %{binary: tenant <> "-crash", filename: "crash.jpg", mime_type: "image/jpeg"}

    {pid, monitor} =
      spawn_monitor(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Ingestion.run(DocumentOcr.BlobOwner.owner(), [upload], fn [blob] ->
            send(parent, {:stored, blob})

            receive do
              :finish -> {:ok, blob}
            end
          end)
        end)
      end)

    assert_receive {:stored, blob}, 5000
    assert {:ok, _} = Local.get(blob.key)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000

    Sandbox.unboxed_run(Repo, fn ->
      assert {:ok, _} =
               Reconciliation.run(
                 DocumentOcr.BlobOwner.owner(),
                 DateTime.add(DateTime.utc_now(), 7200),
                 3600
               )

      assert is_nil(Repo.get(Blob, blob.id))
    end)

    assert {:error, :not_found} = Local.get(blob.key)
  end
end
