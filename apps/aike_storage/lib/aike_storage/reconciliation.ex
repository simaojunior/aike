defmodule AikeStorage.Reconciliation do
  @moduledoc """
  Retries orphan cleanup after crashes, for one owner's database and folder only.

  Unreferenced blobs past the grace period are deleted, then every file in the owner's
  folder without a blob row is removed. Live references and writes younger than the grace
  period win. Another service's folder is never listed, so a shared bucket is safe.

  ## Examples

      {:ok, %{blobs_deleted: 0, objects_checked: 12}} = AikeStorage.Reconciliation.run(owner)
  """
  alias AikeStorage.Adapter.{Local, S3}
  alias AikeStorage.{Blobs, LocalInventory, Owner}
  alias AikeStorage.Transaction

  @doc """
  Runs one reconciliation pass.

  ## Parameters
    - owner: the owner to reconcile
    - now: the current time
    - grace_seconds: age below which blobs and files are left alone

  ## Returns
    - `{:ok, %{blobs_deleted: count, objects_checked: count}}` or the first error
  """
  @spec run(Owner.t(), DateTime.t(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def run(%Owner{} = owner, now \\ DateTime.utc_now(), grace_seconds \\ 3600) do
    with {:ok, blobs} <- Blobs.purge_expired(owner, now, grace_seconds),
         {:ok, inventory} <- inventory(Application.fetch_env!(:aike_storage, :adapter), owner),
         {:ok, checked} <- sweep(owner, inventory, DateTime.to_unix(now) - grace_seconds) do
      {:ok, %{blobs_deleted: blobs, objects_checked: checked}}
    end
  end

  defp inventory(Local, owner), do: LocalInventory.list(owner.folder)
  defp inventory(S3, owner), do: S3.list(owner.folder)
  defp inventory(_adapter, _owner), do: {:ok, []}

  defp sweep(owner, objects, cutoff) do
    objects
    |> Enum.filter(&(&1.modified <= cutoff))
    |> Enum.reduce_while({:ok, 0}, fn object, {:ok, count} ->
      counted(clean(owner, object), count)
    end)
  end

  defp clean(owner, %{temporary: false} = object),
    do: Blobs.compensate(owner, object.hash, object.key)

  defp clean(owner, object) do
    result =
      Transaction.run(owner.repo, {:blob, object.hash}, fn ->
        with :ok <- LocalInventory.delete_temporary(object.key, owner.folder), do: {:ok, :ok}
      end)

    unwrap(result)
  end

  defp unwrap({:ok, :ok}), do: :ok
  defp unwrap(error), do: error
  defp counted(:ok, count), do: {:cont, {:ok, count + 1}}
  defp counted(error, _), do: {:halt, error}
end
