defmodule AikeStorage.Transaction do
  @moduledoc "Database-scoped serialization and atomic tagged-result transactions."
  @spec lock(module(), term()) :: :ok
  def lock(repo, identity) do
    # A collision only serializes unrelated work; it cannot conflate identities.
    key = :erlang.phash2(identity, 2_147_483_648)
    _ = repo.query!("SELECT pg_advisory_xact_lock(424202, $1)", [key])
    :ok
  end

  @spec run(module(), term(), (-> term())) :: term()
  def run(repo, identity, fun) do
    repo.transaction(fn ->
      lock(repo, identity)
      unwrap(repo, fun.())
    end)
    |> result()
  end

  defp unwrap(_repo, {:ok, value}), do: value
  defp unwrap(repo, {:error, reason}), do: repo.rollback(reason)

  defp unwrap(repo, {:error, step, reason, changes}),
    do: repo.rollback({:multi_failure, step, reason, changes})

  defp result({:error, {:multi_failure, step, reason, changes}}),
    do: {:error, step, reason, changes}

  defp result(result), do: result
end
