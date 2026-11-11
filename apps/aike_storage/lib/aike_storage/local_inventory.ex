defmodule AikeStorage.LocalInventory do
  @moduledoc """
  Inventory of the local storage adapter's files, one owner folder at a time.

  Only managed regular files are listed: `<sha256>.<extension>` and the temporaries an
  atomic write leaves behind after a crash. Links and other files are ignored.
  """
  @filename ~r/\A(?<hash>[a-f0-9]{64})\.[a-zA-Z0-9]{1,16}(?<temporary>\.[A-F0-9]+\.tmp)?\z/

  @doc """
  Lists the managed files of one folder.

  ## Parameters
    - folder: the owner's folder, such as `"kyc_documents"`

  ## Returns
    - `{:ok, files}` with `key`, `hash`, `modified` (Unix time) and `temporary`
    - `{:error, :storage_unavailable}`
  """
  @spec list(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list(folder) do
    directory = Path.join(Application.fetch_env!(:aike_storage, :local_root), folder)
    entries = File.ls(directory)
    inventory(entries, directory, folder)
  end

  defp inventory({:error, :enoent}, _, _), do: {:ok, []}
  defp inventory({:error, _}, _, _), do: {:error, :storage_unavailable}

  defp inventory({:ok, names}, directory, folder) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, files} ->
      inspect_entry(Regex.named_captures(@filename, name), {directory, folder}, name, files)
    end)
  end

  defp inspect_entry(nil, _, _, files), do: {:cont, {:ok, files}}

  defp inspect_entry(captures, {directory, folder}, name, files) do
    stat = File.lstat(Path.join(directory, name), time: :posix)
    append(stat, captures, {folder, name}, files)
  end

  defp append({:ok, %{type: :regular, mtime: modified}}, captures, {folder, name}, files) do
    file = %{
      key: folder <> "/" <> name,
      hash: captures["hash"],
      modified: modified,
      temporary: captures["temporary"] != ""
    }

    {:cont, {:ok, [file | files]}}
  end

  defp append({:ok, _}, _, _, files), do: {:cont, {:ok, files}}
  defp append({:error, :enoent}, _, _, files), do: {:cont, {:ok, files}}
  defp append(_, _, _, _), do: {:halt, {:error, :storage_unavailable}}

  @doc """
  Deletes an abandoned temporary file of a folder.

  ## Parameters
    - key: the temporary file's key
    - folder: the owner's folder; keys outside it are refused

  ## Returns
    - `:ok`, also when the file is already gone
    - `{:error, :invalid_key}` for a key that is not a temporary file of the folder
    - `{:error, :storage_unavailable}`
  """
  @spec delete_temporary(String.t(), String.t()) ::
          :ok | {:error, :invalid_key | :storage_unavailable}
  def delete_temporary(key, folder) do
    prefix = folder <> "/"

    with true <- String.starts_with?(key, prefix),
         name = String.replace_prefix(key, prefix, ""),
         %{"temporary" => temporary} when temporary != "" <- Regex.named_captures(@filename, name) do
      root = Application.fetch_env!(:aike_storage, :local_root)
      deleted(File.rm(Path.join(root, key)))
    else
      _ -> {:error, :invalid_key}
    end
  end

  defp deleted(:ok), do: :ok
  defp deleted({:error, :enoent}), do: :ok
  defp deleted(_), do: {:error, :storage_unavailable}
end
