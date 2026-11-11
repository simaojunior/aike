defmodule Biometrics.ReuseTestEngine do
  @behaviour Biometrics.Engine
  def compare(selfie, document, _opts) do
    send(self(), {:compared, selfie, document})

    if selfie == "failure" do
      {:error, :unavailable}
    else
      {:ok,
       %{
         "match" => selfie != "bad",
         "similarity_score" => if(selfie == "bad", do: 0.2, else: 0.98)
       }}
    end
  end
end

defmodule Biometrics.ResultReuseTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Biometrics.Repo
  alias Biometrics.{Facematches, Repo, Workers.CompareFaces}
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    engine = Application.fetch_env!(:biometrics, :engine)
    version = Application.fetch_env!(:biometrics, :engine_version)
    Application.put_env(:biometrics, :engine, Biometrics.ReuseTestEngine)

    on_exit(fn ->
      Application.put_env(:biometrics, :engine, engine)
      Application.put_env(:biometrics, :engine_version, version)
    end)

    :ok
  end

  defp create(selfie, document \\ "document", company \\ "company-a") do
    {:ok, selfie_blob} =
      AikeStorage.Blobs.put(selfie, "selfie.jpg", "image/jpeg", Biometrics.BlobOwner.owner())

    {:ok, document_blob} =
      AikeStorage.Blobs.put(document, "document.jpg", "image/jpeg", Biometrics.BlobOwner.owner())

    Facematches.create(%{
      app_id: company,
      external_id: "person",
      selfie_blob_id: selfie_blob.id,
      document_blob_id: document_blob.id
    })
  end

  test "same pair reuses completed result; better selfie runs again" do
    {:ok, %{session: bad}} = create("bad")
    assert :ok = perform_job(CompareFaces, %{"id" => bad.id})
    assert_received {:compared, "bad", "document"}

    assert {:ok, %{session: reused, job: nil, reused: true}} = create("bad")
    assert reused.id == bad.id
    refute reused.result.data["match"]
    refute_received {:compared, _, _}

    {:ok, %{session: good, job: job}} = create("good")
    assert job
    refute good.id == bad.id
    assert :ok = perform_job(CompareFaces, %{"id" => good.id})
    assert_received {:compared, "good", "document"}
    assert Facematches.get(good.id).result.data["match"]
    assert :ok = perform_job(CompareFaces, %{"id" => good.id})
    refute_received {:compared, _, _}
  end

  test "reuse requires same company, ordered image pair and model version" do
    {:ok, %{session: original}} = create("selfie")
    assert :ok = perform_job(CompareFaces, %{"id" => original.id})

    for {selfie, document, company} <- [
          {"selfie", "new-document", "company-a"},
          {"document", "selfie", "company-a"},
          {"selfie", "document", "company-b"}
        ] do
      assert {:ok, %{session: session, job: job}} = create(selfie, document, company)
      refute session.id == original.id
      assert job
    end

    Application.put_env(:biometrics, :engine_version, "v2")
    assert {:ok, %{session: session, job: job}} = create("selfie")
    refute session.id == original.id
    assert job
  end

  test "a transient engine failure keeps one pending request and does not cache a result" do
    {:ok, %{session: session}} = create("failure")
    assert {:error, :unavailable} = perform_job(CompareFaces, %{"id" => session.id})
    assert {:ok, %{session: retry, job: job}} = create("failure")
    assert retry.id == session.id
    assert is_nil(retry.result)
    assert is_nil(job)
  end

  test "worker does not label a changed engine as the original model version" do
    {:ok, %{session: session}} = create("selfie")
    Application.put_env(:biometrics, :engine_version, "v2")

    assert {:error, :engine_version_unavailable} =
             perform_job(CompareFaces, %{"id" => session.id})

    refute_received {:compared, _, _}
  end
end
