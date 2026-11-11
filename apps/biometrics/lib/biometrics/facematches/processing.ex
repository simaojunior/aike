defmodule Biometrics.Facematches.Processing do
  @moduledoc "Serializes delivery retries and records exhausted face comparisons as terminal failures."
  use Biometrics, :repository
  alias Biometrics.Facematches.{FacematchRepo, FacematchSession}

  @spec run(String.t(), non_neg_integer(), pos_integer(), (FacematchSession.t() -> term())) ::
          term()
  def run(id, attempt, maximum, fun) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, outcome} <-
           Repo.transaction(fn ->
             locked =
               Repo.one(from(s in FacematchSession, where: s.id == ^uuid, lock: "FOR UPDATE"))

             process(locked, attempt >= maximum, fun)
           end) do
      outcome
    else
      :error -> {:cancel, :not_found}
      _ -> {:error, :processing_failed}
    end
  end

  defp process(nil, _, _), do: {:cancel, :not_found}
  defp process(%{status: status}, _, _) when status in ["completed", "failed"], do: :ok

  defp process(session, exhausted, fun) do
    outcome = fun.(FacematchRepo.get(session.id))
    record(outcome, session, exhausted)
  end

  defp record({:error, _} = error, session, true) do
    {:ok, failed} = Repo.update(Ecto.Changeset.change(session, status: "failed"))
    :ok = Biometrics.Completion.notify(failed)
    error
  end

  defp record(outcome, _, _), do: outcome
end
