defmodule AikeStorage.Blobs do
  @moduledoc """
  Content-addressed blobs with serialized writes and reference-safe deletion.

  Every operation receives the `AikeStorage.Owner` of the blobs: its Repo holds the
  `blobs` rows and its references decide whether a blob is still in use. Writes and
  deletions of the same content are serialized by an advisory lock on the hash. A row is
  deleted before its file, so a failed deletion keeps the bytes.

  ## Errors
    - `:blob_in_use`: a row of the owner still references the blob
    - `:storage_unavailable`: the storage adapter failed

  ## Examples

      {:ok, blob} = AikeStorage.Blobs.put(bytes, "front.jpg", "image/jpeg", owner)
      {:ok, ^bytes} = AikeStorage.Blobs.get(blob)
  """
  alias AikeStorage.{Blob, Key, Owner}
  alias AikeStorage.Transaction

  @purge_batch 100

  @doc """
  Stores bytes once per content and returns their blob.

  ## Parameters
    - binary: the file bytes
    - filename: the original name, for the extension
    - mime_type: the declared MIME type
    - owner: the owner of the blob

  ## Returns
    - `{:ok, blob}`, new or existing
    - `{:error, changeset}` or `{:error, :storage_unavailable}`
  """
  @spec put(binary(), String.t() | nil, String.t() | nil, Owner.t()) ::
          {:ok, Blob.t()} | {:error, term()}
  def put(binary, filename, mime_type, %Owner{repo: repo} = owner) do
    identity = Key.for(binary, filename, mime_type: mime_type, folder: owner.folder)
    put_transaction(repo.in_transaction?(), owner, binary, mime_type, identity)
  end

  defp put_transaction(true, owner, binary, mime, {hash, _, _} = identity) do
    Transaction.lock(owner.repo, {:blob, hash})
    put_locked(owner.repo, binary, mime, identity)
  end

  defp put_transaction(false, owner, binary, mime, {hash, key, _} = identity) do
    result =
      Transaction.run(owner.repo, {:blob, hash}, fn ->
        put_locked(owner.repo, binary, mime, identity)
      end)

    compensate_failure(result, owner, hash, key)
  end

  defp compensate_failure({:error, _} = error, owner, hash, key) do
    _ = compensate(owner, hash, key)
    error
  end

  defp compensate_failure(result, _, _, _), do: result

  defp put_locked(repo, binary, mime, {hash, key, extension}) do
    existing = repo.get_by(Blob, sha256: hash)
    write_blob(existing, repo, binary, mime, {hash, key, extension})
  end

  defp write_blob(%Blob{} = blob, _repo, binary, _mime, _) do
    with :ok <- write(binary, blob.key, blob.sha256), do: {:ok, blob}
  end

  defp write_blob(nil, repo, binary, mime, {hash, key, _extension}) do
    changeset =
      Blob.changeset(%Blob{}, %{
        key: key,
        sha256: hash,
        mime_type: mime || "application/octet-stream",
        byte_size: byte_size(binary)
      })

    with true <- changeset.valid?,
         :ok <- write(binary, key, hash),
         {:ok, blob} <- repo.insert(changeset) do
      {:ok, blob}
    else
      false -> {:error, changeset}
      error -> error
    end
  end

  defp write(binary, key, hash) do
    opts = [
      folder: Path.dirname(key),
      sha256: hash,
      extension: Path.extname(key) |> String.trim_leading(".")
    ]

    case adapter().put(binary, opts) do
      {:ok, ^key} -> :ok
      _ -> {:error, :storage_unavailable}
    end
  end

  @doc """
  Reads the bytes of a blob or a storage key.

  ## Parameters
    - blob: a `Blob` or a key

  ## Returns
    - `{:ok, bytes}` or the adapter error
  """
  @spec get(Blob.t() | String.t()) :: {:ok, binary()} | {:error, term()}
  def get(%Blob{key: key}), do: adapter().get(key)
  def get(key) when is_binary(key), do: adapter().get(key)

  @doc """
  Deletes a blob row and its file when no row of the owner references it.

  ## Parameters
    - blob: the blob
    - owner: its owner

  ## Returns
    - `:ok`, also when the blob is already gone
    - `{:error, :blob_in_use}` or the adapter error
  """
  @spec delete(Blob.t(), Owner.t()) :: :ok | {:error, term()}
  def delete(%Blob{} = blob, %Owner{} = owner) do
    owner.repo
    |> Transaction.run({:blob, blob.sha256}, fn -> delete_locked(owner, blob) end)
    |> deleted()
  end

  defp delete_locked(owner, blob) do
    import Ecto.Query, only: [from: 2]

    current = owner.repo.one(from(b in Blob, where: b.id == ^blob.id, lock: "FOR UPDATE"))
    delete_current(current, owner)
  end

  defp delete_current(nil, _owner), do: {:ok, :ok}

  defp delete_current(blob, owner) do
    {sql, params} = Owner.referenced_query(owner, Ecto.UUID.dump!(blob.id), blob.key)
    %{rows: [[referenced]]} = owner.repo.query!(sql, params)
    delete_unreferenced(referenced, blob, owner)
  end

  defp delete_unreferenced(true, _blob, _owner), do: {:error, :blob_in_use}

  defp delete_unreferenced(false, blob, owner) do
    changeset =
      owner
      |> Owner.constraints()
      |> Enum.reduce(Ecto.Changeset.change(blob), fn name, changeset ->
        Ecto.Changeset.foreign_key_constraint(changeset, :id, name: name)
      end)

    with {:ok, _} <- owner.repo.delete(changeset),
         :ok <- adapter().delete(blob.key) do
      {:ok, :ok}
    else
      {:error, %Ecto.Changeset{}} -> {:error, :blob_in_use}
      error -> error
    end
  end

  defp deleted({:ok, :ok}), do: :ok
  defp deleted(error), do: error

  @doc """
  Removes a file that has no blob row, unless a legacy row references its key.

  Used after a failed write and by reconciliation for files left by a crash.

  ## Parameters
    - owner: the owner of the folder
    - hash: the content hash
    - key: the storage key

  ## Returns
    - `:ok` or the adapter error
  """
  @spec compensate(Owner.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def compensate(%Owner{} = owner, hash, key) do
    owner.repo
    |> Transaction.run({:blob, hash}, fn ->
      compensate_absent(owner.repo.get_by(Blob, sha256: hash), key, owner)
    end)
    |> deleted()
  end

  defp compensate_absent(%Blob{key: key}, key, _owner), do: {:ok, :ok}

  defp compensate_absent(_blob, key, owner) do
    {sql, params} = Owner.key_referenced_query(owner, key)
    %{rows: [[referenced]]} = owner.repo.query!(sql, params)
    remove_unreferenced_key(referenced, key)
  end

  defp remove_unreferenced_key(true, _key), do: {:ok, :ok}

  defp remove_unreferenced_key(false, key) do
    with :ok <- adapter().delete(key), do: {:ok, :ok}
  end

  @doc """
  Deletes up to 100 unreferenced blobs older than the grace period.

  ## Parameters
    - owner: the owner
    - now: the current time
    - seconds: the grace period; younger blobs may belong to a write in progress

  ## Returns
    - `{:ok, deleted_count}` or the first adapter error
  """
  @spec purge_expired(Owner.t(), DateTime.t(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def purge_expired(%Owner{} = owner, now, seconds) do
    import Ecto.Query, only: [from: 2]

    cutoff = DateTime.add(now, -seconds, :second)

    %{rows: rows} =
      owner.repo.query!(
        """
        SELECT b.id FROM blobs b
        WHERE b.inserted_at <= $1 AND NOT (#{Owner.referenced_condition(owner)})
        ORDER BY b.inserted_at
        LIMIT #{@purge_batch}
        """,
        [cutoff]
      )

    ids = Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)

    from(blob in Blob, where: blob.id in ^ids, order_by: blob.inserted_at)
    |> owner.repo.all()
    |> Enum.reduce_while({:ok, 0}, fn blob, {:ok, count} ->
      count_deletion(delete(blob, owner), count)
    end)
  end

  defp count_deletion(:ok, count), do: {:cont, {:ok, count + 1}}
  defp count_deletion({:error, :blob_in_use}, count), do: {:cont, {:ok, count}}
  defp count_deletion(error, _count), do: {:halt, error}

  defp adapter, do: Application.fetch_env!(:aike_storage, :adapter)
end
