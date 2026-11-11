defmodule Biometrics.Reconciliation do
  @moduledoc "Terminates abandoned comparisons after retries or missing jobs, preserving active work."
  use Biometrics, :repository
  alias Biometrics.Facematches.FacematchSession
  @worker "Biometrics.Workers.CompareFaces"
  @active ~w(available scheduled executing retryable)

  @spec run() :: {:ok, non_neg_integer()} | {:error, term()}
  def run do
    cutoff = DateTime.add(DateTime.utc_now(), -3600)

    candidates =
      from(s in FacematchSession,
        left_join: j in Oban.Job,
        on: fragment("?->>'id' = ?::text", j.args, s.id) and j.worker == ^@worker,
        where:
          s.status in ["pending", "processing"] and
            (j.state in ["discarded", "cancelled"] or s.updated_at < ^cutoff),
        distinct: true,
        select: s.id,
        limit: 100
      )
      |> Repo.all()

    Enum.reduce_while(candidates, {:ok, 0}, fn id, {:ok, count} ->
      counted(reconcile(id, cutoff), count)
    end)
  end

  defp reconcile(id, cutoff) do
    Repo.transaction(fn ->
      session = Repo.one(from(s in FacematchSession, where: s.id == ^id, lock: "FOR UPDATE"))
      repair(session, cutoff)
    end)
  end

  defp repair(%{status: status} = session, cutoff) when status in ["pending", "processing"] do
    jobs =
      from(j in Oban.Job,
        where: fragment("?->>'id' = ?", j.args, ^session.id) and j.worker == ^@worker
      )

    active = Repo.exists?(from(j in jobs, where: j.state in ^@active))

    abandoned =
      DateTime.before?(session.updated_at, cutoff) or
        Repo.exists?(from(j in jobs, where: j.state in ["discarded", "cancelled"]))

    fail_abandoned(not active and abandoned, session)
  end

  defp repair(_, _), do: 0
  defp fail_abandoned(false, _), do: 0

  defp fail_abandoned(true, session) do
    {:ok, _} = Repo.update(Ecto.Changeset.change(session, status: "failed"))
    1
  end

  defp counted({:ok, changed}, count), do: {:cont, {:ok, count + changed}}
  defp counted(error, _), do: {:halt, error}
end
