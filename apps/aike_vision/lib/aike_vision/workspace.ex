defmodule AikeVision.Workspace do
  @moduledoc """
  Private temporary directory for one document, with a total time limit.

  The work runs in a separate process that is killed at the deadline. The calling process
  owns the directory (permissions `0700`), so the directory is removed even when the work
  is killed, raises or exits.

  ## Errors
    - `:timeout`: the work passed the deadline
    - `:runtime_exception`: the work raised or exited
    - `:temporary_directory_failed`: the directory could not be created

  ## Examples

      AikeVision.Workspace.run(fn directory -> read_document(bytes, directory) end, 10_000)
  """

  @doc """
  Runs `fun` with a new private directory and removes the directory afterwards.

  ## Parameters
    - fun: function that receives the directory path and returns `{:ok, result}` or
      `{:error, reason}`
    - timeout_ms: total time limit for `fun`, in milliseconds

  ## Returns
    - the value returned by `fun`
    - `{:error, :timeout | :runtime_exception | :temporary_directory_failed}`

  ## Example

      {:ok, text} = AikeVision.Workspace.run(&extract(bytes, &1), 10_000)
  """
  @spec run((Path.t() -> {:ok, result} | {:error, term()}), pos_integer()) ::
          {:ok, result} | {:error, term()}
        when result: term()
  def run(fun, timeout_ms) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "aike-vision-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
      )

    with :ok <- File.mkdir(directory),
         :ok <- File.chmod(directory, 0o700) do
      try do
        task = Task.async(fn -> guarded(fun, directory) end)

        case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, result} -> result
          {:exit, _} -> {:error, :runtime_exception}
          nil -> {:error, :timeout}
        end
      after
        File.rm_rf(directory)
      end
    else
      _ ->
        File.rm_rf(directory)
        {:error, :temporary_directory_failed}
    end
  end

  defp guarded(fun, directory) do
    fun.(directory)
  rescue
    _ -> {:error, :runtime_exception}
  catch
    _, _ -> {:error, :runtime_exception}
  end
end
