defmodule AikeStorage.Blobs do
  import Ecto.Query

  alias AikeStorage.{Blob, Key}

  def put(binary, filename, mime_type, opts \\ []) when is_binary(binary) do
    {sha256, key, extension} = Key.for(binary, filename, mime_type: mime_type)

    with {:ok, ^key} <- adapter().put(binary, folder: "kyc_documents", sha256: sha256, extension: extension),
         {:ok, blob} <- repo(opts).insert(Blob.changeset(%Blob{}, %{key: key, sha256: sha256, mime_type: mime_type || "application/octet-stream", byte_size: byte_size(binary)})) do
      {:ok, blob}
    end
  end

  def get(%Blob{key: key}), do: adapter().get(key)
  def get(key) when is_binary(key), do: adapter().get(key)

  @doc "Deletes one object from the adapter and then removes its blob record."
  @spec delete(Blob.t(), keyword()) :: :ok | {:error, term()}
  def delete(%Blob{key: key} = blob, opts \\ []) do
    with :ok <- adapter().delete(key), {:ok, _deleted} <- repo(opts).delete(blob) do
      :ok
    end
  end

  @doc "Purges blobs older than the configured retention period."
  @spec purge_expired(Ecto.Repo.t(), DateTime.t(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def purge_expired(repo, now, seconds) do
    expired =
      from(blob in Blob,
        where: blob.inserted_at <= ^DateTime.add(now, -seconds, :second)
      )
      |> repo.all()

    deleted = Enum.count(expired, &match?(:ok, delete(&1, repo: repo)))
    {:ok, deleted}
  end

  defp adapter, do: Application.fetch_env!(:aike_storage, :adapter)
  defp repo(opts), do: Keyword.get(opts, :repo, Application.fetch_env!(:aike_storage, :repo))
end
