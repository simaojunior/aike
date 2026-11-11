defmodule AikeVision.Command do
  @moduledoc """
  Runs a system executable with a hard time limit.

  The executable receives an argument list, never a shell string, and is killed with
  `SIGKILL` at the deadline through GNU `timeout`. Each command runs with
  `OMP_THREAD_LIMIT=1`, so one OCR process uses one core. Commands write their real output
  to files; the captured stream only carries diagnostics, which callers must not log
  because it can contain document text.

  ## Errors
    - `:timeout`: the command passed its deadline and was killed
    - `:missing_runtime_dependency`: the executable (or `timeout`) is not in the `PATH`
    - `:command_failed`: the command exited with another non-zero status

  ## Examples

      {:ok, _diagnostics} = AikeVision.Command.run("pdfinfo", ["/tmp/work/input.pdf"])
  """

  @type error :: :timeout | :missing_runtime_dependency | :command_failed

  @doc """
  Runs `executable` with `args` and waits for it to finish.

  ## Parameters
    - executable: name of the program in the `PATH`
    - args: list of arguments, passed without a shell
    - opts: `:timeout_seconds` (default `4`)

  ## Returns
    - `{:ok, output}` when the command exits with status 0
    - `{:error, :timeout | :missing_runtime_dependency | :command_failed}` otherwise

  ## Example

      {:ok, _} = AikeVision.Command.run("tesseract", [input, output, "-l", "por", "tsv"])
  """
  @spec run(String.t(), [String.t()], keyword()) :: {:ok, String.t()} | {:error, error()}
  def run(executable, args, opts \\ []) do
    seconds = Keyword.get(opts, :timeout_seconds, 4)

    {output, status} =
      System.cmd("timeout", ["--signal=KILL", "#{seconds}s", executable | args],
        stderr_to_stdout: true,
        env: [{"OMP_THREAD_LIMIT", "1"}]
      )

    case status do
      0 -> {:ok, output}
      status when status in [124, 137] -> {:error, :timeout}
      status when status in [126, 127] -> {:error, :missing_runtime_dependency}
      _ -> {:error, :command_failed}
    end
  rescue
    ErlangError -> {:error, :missing_runtime_dependency}
  end
end
