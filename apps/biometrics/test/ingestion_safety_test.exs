defmodule Biometrics.IngestionSafetyTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Biometrics.Repo
  import Ecto.Query
  alias AikeStorage.Adapter.Fake
  alias AikeStorage.{Blob, Blobs}
  alias Biometrics.{Facematches, Repo}
  alias Biometrics.Facematches.FacematchSession
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    Fake.reset()
    :ok
  end

  defp attrs(key) do
    {:ok, selfie} = Blobs.put("selfie", "selfie.jpg", "image/jpeg", Biometrics.BlobOwner.owner())

    {:ok, document} =
      Blobs.put("document", "document.jpg", "image/jpeg", Biometrics.BlobOwner.owner())

    %{
      app_id: "tenant",
      external_id: "subject",
      selfie_blob_id: selfie.id,
      document_blob_id: document.id,
      idempotency_key: key
    }
  end

  test "key replay is stable, conflicting payloads fail and discarded work can be retried with a new key" do
    original = attrs("same")
    {:ok, first} = Facematches.create(original)
    assert {:ok, replay} = Facematches.create(original)
    assert replay.session.id == first.session.id

    assert {:error, :idempotency_conflict} =
             Facematches.create(%{original | external_id: "changed"})

    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.job.id), set: [state: "discarded"])
    assert {:ok, 1} = Biometrics.Reconciliation.run()
    assert Facematches.get(first.session.id).status == "failed"
    assert {:ok, second} = Facematches.create(%{original | idempotency_key: "new"})
    refute second.session.id == first.session.id
    assert {:ok, repeated_failure} = Facematches.create(original)
    assert repeated_failure.session.id == first.session.id
    assert repeated_failure.session.status == "failed"
  end

  test "duplicate completion preserves the first result and creates only one result row" do
    {:ok, %{session: session}} = Facematches.create(attrs(nil))
    first = %{"match" => true, "similarity_score" => 0.95}
    assert {:ok, _} = Facematches.complete(session, first)

    assert {:ok, _} =
             Facematches.complete(session, %{"match" => false, "similarity_score" => 0.01})

    assert Facematches.get(session.id).result.data == first
    assert Repo.aggregate(Biometrics.Facematches.FacematchResult, :count) == 1
  end

  test "invalid second upload leaves no first blob, file or session" do
    path = Path.join(System.tmp_dir!(), "aike-bio-safety-#{Ecto.UUID.generate()}")
    File.write!(path, "first-only")
    on_exit(fn -> File.rm(path) end)
    upload = %Plug.Upload{path: path, filename: "first.jpg", content_type: "image/jpeg"}

    assert {:error, :invalid_upload} =
             Facematches.create_from_uploads(
               %{app_id: "tenant", external_id: "subject"},
               upload,
               "invalid"
             )

    assert Repo.aggregate(Blob, :count) == 0
    assert Repo.aggregate(FacematchSession, :count) == 0
  end
end
