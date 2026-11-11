defmodule Biometrics.Facematches.FacematchRepo do
  @moduledoc "Queries and transactions for facematch sessions and results."
  @dialyzer {:nowarn_function, create: 1}
  @dialyzer {:nowarn_function, complete_new: 2}
  # Ecto.Multi's MapSet representation triggers an OTP 28 opaque-type false positive.
  @dialyzer {:nowarn_function, create_new: 2}

  use Biometrics, :repository

  alias Biometrics.Facematches.{FacematchResult, FacematchSession}

  @spec get(Ecto.UUID.t()) :: FacematchSession.t() | nil
  def get(id), do: Repo.get(FacematchSession, id) |> preload()

  @spec get(String.t(), Ecto.UUID.t()) :: FacematchSession.t() | nil
  def get(app_id, id), do: Repo.get_by(FacematchSession, id: id, app_id: app_id) |> preload()

  @spec create(map()) :: {:ok, map()} | {:error, term()} | {:error, term(), term(), map()}
  def create(attrs) do
    profile = %{
      engine: inspect(Application.fetch_env!(:biometrics, :engine)),
      engine_version: Application.fetch_env!(:biometrics, :engine_version)
    }

    changeset = FacematchSession.changeset(%FacematchSession{}, attrs)

    fingerprint =
      KycCore.Idempotency.fingerprint(
        attrs
        |> Map.take([:selfie_blob_id, :document_blob_id])
        |> Map.put(:external_id, Map.get(attrs, :requested_external_id, attrs[:external_id]))
      )

    Biometrics.Requests.run(
      Repo,
      :facematch,
      attrs.app_id,
      attrs[:idempotency_key],
      fingerprint,
      fn ->
        AikeStorage.Transaction.run(
          Repo,
          {:facematch_content, Map.take(attrs, [:app_id, :selfie_blob_id, :document_blob_id]),
           profile},
          fn -> create_valid(changeset, attrs, profile) end
        )
      end,
      fn id -> replay(get(id)) end
    )
  end

  defp create_valid(%{valid?: false}, _attrs, _profile), do: {:error, :invalid_request}

  defp create_valid(changeset, attrs, profile) do
    completed = completed(attrs, profile)
    reuse_or_create(completed, changeset, profile)
  end

  defp reuse_or_create(nil, changeset, profile), do: create_new(changeset, profile)
  defp reuse_or_create(session, _changeset, _profile), do: replay(session)

  defp replay(session),
    do: {:ok, %{session: session, job: nil, reused: session.status in ["completed", "failed"]}}

  defp completed(attrs, profile) do
    from(session in FacematchSession,
      left_join: result in assoc(session, :result),
      where:
        session.app_id == ^attrs.app_id and
          session.selfie_blob_id == ^attrs.selfie_blob_id and
          session.document_blob_id == ^attrs.document_blob_id and
          session.engine == ^profile.engine and session.engine_version == ^profile.engine_version and
          (session.status in ["pending", "processing"] or
             (session.status == "completed" and not is_nil(result.id))),
      order_by: [desc: session.inserted_at],
      limit: 1,
      preload: [:result, :selfie_blob, :document_blob]
    )
    |> Repo.one()
  end

  defp create_new(changeset, profile) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:session, Ecto.Changeset.change(changeset, profile))
    |> Ecto.Multi.run(:job, fn _repo, %{session: session} ->
      Oban.insert(Biometrics.Oban, Biometrics.Workers.CompareFaces.new(%{id: session.id}))
    end)
    |> Repo.transaction()
  end

  @spec complete(FacematchSession.t(), map()) :: {:ok, map()} | {:error, term()}
  def complete(session, data) do
    Repo.transaction(fn ->
      current =
        Repo.one!(from(s in FacematchSession, where: s.id == ^session.id, lock: "FOR UPDATE"))

      finish(current, data)
    end)
  end

  defp finish(%{status: "completed"} = session, _data), do: %{session: preload(session)}

  defp finish(session, data) do
    result = complete_new(session, data)
    unwrap_completion(result)
  end

  defp unwrap_completion({:ok, value}), do: value

  defp unwrap_completion({:error, step, reason, changes}),
    do: Repo.rollback({step, reason, changes})

  defp complete_new(session, data) do
    %{matched: matched, decision: decision} = Biometrics.Decision.decide(data["similarity_score"])

    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :result,
      FacematchResult.changeset(%FacematchResult{}, %{session_id: session.id, data: data})
    )
    |> Ecto.Multi.update(
      :session,
      Ecto.Changeset.change(session,
        status: "completed",
        decision: decision,
        matched: matched,
        similarity_score: data["similarity_score"],
        selfie_face_detected: Map.get(data, "selfie_face_detected", true),
        document_face_detected: Map.get(data, "document_face_detected", true)
      )
    )
    |> Ecto.Multi.run(:notified, fn _repo, %{session: completed} ->
      {:ok, Biometrics.Completion.notify(completed)}
    end)
    |> Repo.transaction()
  end

  defp preload(nil), do: nil
  defp preload(session), do: Repo.preload(session, [:result, :selfie_blob, :document_blob])
end
