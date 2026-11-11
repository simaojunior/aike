defmodule DocumentOcr.OCR.TesseractPython do
  @moduledoc """
  Reference engine: the same pipeline as `DocumentOcr.OCR.Tesseract`, written as the Python
  script `priv/ocr_lines.py`. Kept to compare results; registered but not the default.
  """
  @behaviour DocumentOcr.OCR.Engine
  require Logger

  @version "tesseract-5-por-1"
  @max_bytes 10_000_000

  def version, do: @version

  @impl true
  def extract(bytes, opts) do
    cond do
      Keyword.get(opts, :engine_version) != @version -> {:error, :unsupported_engine_version}
      not is_binary(bytes) or byte_size(bytes) == 0 -> {:error, :invalid_image}
      byte_size(bytes) > @max_bytes -> {:error, :invalid_image}
      true -> in_private_directory(bytes)
    end
  end

  defp in_private_directory(bytes) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "aike-ocr-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
      )

    case File.mkdir(directory) do
      :ok -> read_in(directory, bytes)
      {:error, _} -> unavailable(:temporary_directory_failed)
    end
  rescue
    _ -> unavailable(:runtime_exception)
  end

  defp read_in(directory, bytes) do
    with :ok <- File.chmod(directory, 0o700),
         :ok <- File.write(Path.join(directory, "input"), bytes),
         {:ok, output} <- run(directory),
         {:ok, %{"text" => lines}} when is_list(lines) <- Jason.decode(output) do
      {:ok, %{"text" => lines}}
    else
      {:error, :invalid_image} -> {:error, :invalid_image}
      {:error, {:unavailable, _}} = error -> error
      _ -> unavailable(:invalid_output)
    end
  after
    File.rm_rf(directory)
  end

  defp run(directory) do
    script = Application.app_dir(:document_ocr, "priv/ocr_lines.py")

    "timeout"
    |> System.cmd(
      ["--signal=KILL", "12s", "python3", script, Path.join(directory, "input"), directory],
      stderr_to_stdout: true,
      env: [{"OMP_THREAD_LIMIT", "1"}]
    )
    |> decode_exit()
  end

  defp decode_exit({output, 0}), do: {:ok, output}
  defp decode_exit({_, 2}), do: {:error, :invalid_image}
  defp decode_exit({_, 3}), do: unavailable(:missing_runtime_dependency)
  defp decode_exit({_, status}) when status in [4, 124, 137], do: unavailable(:timeout)
  defp decode_exit({_, 5}), do: unavailable(:ocr_command_failed)
  defp decode_exit(_), do: unavailable(:subprocess_failed)

  defp unavailable(reason) do
    Logger.error("Tesseract OCR failed: #{reason}", event: "ocr.tesseract.failed")
    {:error, {:unavailable, reason}}
  end
end
