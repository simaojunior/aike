defmodule AikeStorage.Adapter.Local do
  @moduledoc "Persistent local private storage using content-addressed keys and atomic writes."
  @behaviour AikeStorage.Adapter

  @impl true
  def put(data, opts) when is_binary(data) do
    sha256 = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

    key =
      "#{Keyword.get(opts, :folder, "kyc_documents")}/#{sha256}.#{Keyword.fetch!(opts, :extension)}"

    with true <- sha256 == Keyword.fetch!(opts, :sha256),
         {:ok, path} <- path(key),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- write_atomic(path, data) do
      {:ok, key}
    else
      false -> {:error, :invalid_checksum}
      {:error, :invalid_key} = error -> error
      _ -> {:error, :storage_unavailable}
    end
  end

  @impl true
  def get(key) do
    with {:ok, path} <- path(key) do
      case File.read(path) do
        {:ok, data} -> {:ok, data}
        {:error, :enoent} -> {:error, :not_found}
        _ -> {:error, :storage_unavailable}
      end
    end
  end

  @impl true
  def delete(key) do
    with {:ok, path} <- path(key) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        _ -> {:error, :storage_unavailable}
      end
    end
  end

  defp path(key) when is_binary(key) do
    if Regex.match?(~r/\A[a-zA-Z0-9_-]+\/[a-f0-9]{64}\.[a-zA-Z0-9]{1,16}\z/, key) do
      root = Application.fetch_env!(:aike_storage, :local_root)
      {:ok, Path.join(root, key)}
    else
      {:error, :invalid_key}
    end
  end

  defp path(_), do: {:error, :invalid_key}

  defp write_atomic(path, data) do
    temp = path <> "." <> Base.encode16(:crypto.strong_rand_bytes(12)) <> ".tmp"

    try do
      with :ok <- File.write(temp, "", [:binary, :exclusive]),
           :ok <- File.chmod(temp, 0o600),
           :ok <- File.write(temp, data, [:binary, :sync]) do
        File.rename(temp, path)
      end
    after
      File.rm(temp)
    end
  end
end
