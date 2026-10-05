defmodule Biometrics.Facematches do
  @dialyzer {:nowarn_function, create: 1}
  @dialyzer {:nowarn_function, complete: 2}

  alias Biometrics.{FacematchResult, FacematchSession, Repo}

  def get(id), do: Repo.get(FacematchSession, id) |> preload()

  def create(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:session, FacematchSession.changeset(%FacematchSession{}, attrs))
    |> Ecto.Multi.run(:job, fn _repo, %{session: session} ->
      Oban.insert(Biometrics.Oban, Biometrics.Workers.CompareFaces.new(%{id: session.id}))
    end)
    |> Repo.transaction()
  end

  def complete(session, data) do
    decision = if data["match"], do: "approved", else: "rejected"

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:result, FacematchResult.changeset(%FacematchResult{}, %{session_id: session.id, data: data}))
    |> Ecto.Multi.update(:session, Ecto.Changeset.change(session,
      status: "completed",
      decision: decision,
      matched: data["match"],
      similarity_score: data["similarity_score"],
      selfie_face_detected: Map.get(data, "selfie_face_detected", true),
      document_face_detected: Map.get(data, "document_face_detected", true)
    ))
    |> Repo.transaction()
  end

  defp preload(nil), do: nil
  defp preload(session), do: Repo.preload(session, [:result, :selfie_blob, :document_blob])
end
