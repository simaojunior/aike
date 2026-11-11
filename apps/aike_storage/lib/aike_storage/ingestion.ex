defmodule AikeStorage.Ingestion do
  @moduledoc """
  Commits blob rows and the records that use them in one transaction.

  Blobs are locked by hash in a fixed order, written, then passed to `create`. When the
  transaction rolls back, the files written for new blobs are removed; files of blobs that
  already existed are kept, because other records may use them. A failed removal is
  retried by `AikeStorage.Reconciliation`.

  ## Examples

      AikeStorage.Ingestion.run(owner, uploads, fn blobs -> create_document(blobs) end)
  """
  alias AikeStorage.{Blob, Blobs, Key, Owner}
  alias AikeStorage.Transaction

  @doc """
  Stores uploads and creates their records atomically.

  ## Parameters
    - owner: the owner of the blobs
    - uploads: maps with `binary`, `filename` and `mime_type`
    - create: receives the blobs in upload order; returns `{:ok, value}` or an error

  ## Returns
    - `{:ok, value}`, or the error of a write or of `create`
  """
  @spec run(Owner.t(), [map()], ([Blob.t()] -> term())) :: term()
  def run(%Owner{repo: repo} = owner, uploads, create) do
    result =
      repo.transaction(fn ->
        plans = plan(owner, uploads)

        with {:ok, blobs} <- store(owner, uploads),
             {:ok, value} <- create.(blobs) do
          value
        else
          error -> repo.rollback({:ingestion_failed, error, plans})
        end
      end)

    finish(result, owner)
  end

  defp plan(%Owner{repo: repo} = owner, uploads) do
    keys =
      Enum.map(
        uploads,
        &Key.for(&1.binary, &1.filename, mime_type: &1.mime_type, folder: owner.folder)
      )

    keys
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(&Transaction.lock(repo, {:blob, &1}))

    for {hash, key, _extension} <- keys, is_nil(repo.get_by(Blob, sha256: hash)), do: {hash, key}
  end

  defp store(owner, uploads) do
    Enum.reduce_while(uploads, {:ok, []}, fn upload, {:ok, stored} ->
      result = Blobs.put(upload.binary, upload.filename, upload.mime_type, owner)
      append(result, stored)
    end)
  end

  defp append({:ok, blob}, stored), do: {:cont, {:ok, stored ++ [blob]}}
  defp append(error, _), do: {:halt, error}

  defp finish({:error, {:ingestion_failed, error, plans}}, owner) do
    failures = Enum.count(plans, fn {hash, key} -> Blobs.compensate(owner, hash, key) != :ok end)
    :telemetry.execute([:aike, :storage, :compensation], %{failures: failures}, %{})
    error
  end

  defp finish(result, _owner), do: result
end
