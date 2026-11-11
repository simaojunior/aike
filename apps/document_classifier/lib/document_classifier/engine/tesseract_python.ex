defmodule DocumentClassifier.Engine.TesseractPython do
  @moduledoc """
  Reference engine: the same pipeline as `DocumentClassifier.Engine.Tesseract`, written as
  the Python script `priv/classify_text.py`. Kept to compare results; not the default.
  """
  @behaviour DocumentClassifier.Engine
  alias DocumentClassifier.Engine.TextRules
  require Logger

  @impl true
  def classify(bytes, _opts) when byte_size(bytes) > 0 and byte_size(bytes) <= 10_000_000 do
    directory =
      Path.join(
        System.tmp_dir!(),
        "aike-classifier-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
      )

    case File.mkdir(directory) do
      :ok -> classify_in(directory, bytes)
      {:error, _} -> unavailable(:temporary_directory_failed)
    end
  rescue
    _ -> unavailable(:runtime_exception)
  end

  def classify(_, _), do: {:error, :invalid_request}

  defp classify_in(directory, bytes) do
    with :ok <- File.chmod(directory, 0o700),
         :ok <- File.write(Path.join(directory, "input"), bytes),
         {:ok, output} <- extract(directory),
         {:ok, %{"text" => text, "confidence" => confidence} = extracted} <-
           Jason.decode(output),
         issues when is_list(issues) <- Map.get(extracted, "issues", []),
         true <- Enum.all?(issues, &is_binary/1) do
      {:ok, TextRules.classify(text, confidence, issues)}
    else
      {:error, :invalid_request} -> {:error, :invalid_request}
      _ -> unavailable(:extraction_failed)
    end
  after
    File.rm_rf(directory)
  end

  defp extract(directory) do
    script = Application.app_dir(:document_classifier, "priv/classify_text.py")

    result =
      System.cmd(
        "timeout",
        ["--signal=KILL", "10s", "python3", script, Path.join(directory, "input"), directory],
        stderr_to_stdout: true,
        env: [{"OMP_THREAD_LIMIT", "1"}]
      )

    decode_exit(result)
  end

  defp decode_exit({output, 0}), do: {:ok, output}
  defp decode_exit({_, 2}), do: {:error, :invalid_request}
  defp decode_exit({_, 3}), do: unavailable(:missing_runtime_dependency)
  defp decode_exit({_, status}) when status in [4, 124, 137], do: unavailable(:timeout)
  defp decode_exit({_, 5}), do: unavailable(:ocr_command_failed)
  defp decode_exit(_), do: unavailable(:subprocess_failed)

  defp unavailable(reason) do
    Logger.error("Tesseract extraction failed: #{reason}", event: "classifier.ocr.failed")
    {:error, :service_unavailable}
  end
end
