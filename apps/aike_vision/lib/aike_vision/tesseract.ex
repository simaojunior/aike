defmodule AikeVision.Tesseract do
  @moduledoc """
  Text recognition with the Tesseract executable and its Portuguese model.

  Each call runs one single-threaded Tesseract process. Every process holds a slot of
  `AikeVision.Processes`, so the node never runs more OCR processes than it has cores,
  whatever the number of requests.

  ## Configuration

      config :aike_vision,
        ocr_concurrency: 8

  `:ocr_concurrency` limits the processes of one document (default: one per scheduler).

  ## Examples

      {:ok, words} = AikeVision.Tesseract.words(image, directory, "3")
      {:ok, [gray_words, blue_words]} =
        AikeVision.Tesseract.words_all([{gray, "4"}, {blue, "4"}], directory)
  """
  alias AikeVision.{Command, Image}

  @type word :: %{
          text: String.t(),
          confidence: float(),
          box: {integer(), integer(), integer(), integer()},
          line: {integer(), integer(), integer()}
        }

  @doc """
  Reads the words of one image.

  ## Parameters
    - image: the image to read
    - directory: workspace for the temporary files
    - psm: Tesseract page segmentation mode (`"3"` automatic, `"4"` one column,
      `"11"` sparse text)

  ## Returns
    - `{:ok, words}`: each word with `text`, `confidence` (0 to 100), `box`
      (`{left, top, right, bottom}`) and `line` (`{block, paragraph, line}`)
    - `{:error, reason}` from `AikeVision.Command`, or `:image_write_failed`

  ## Example

      {:ok, [%{text: "NOME", confidence: 91.5} | _]} =
        AikeVision.Tesseract.words(card, directory, "4")
  """
  @spec words(Evision.Mat.t(), Path.t(), String.t()) ::
          {:ok, [word()]} | {:error, Command.error() | :image_write_failed}
  def words(image, directory, psm) do
    name = "ocr-#{System.unique_integer([:positive])}"
    input = Path.join(directory, name <> ".png")
    output = Path.join(directory, name)

    with :ok <- Image.write(image, input),
         {:ok, _} <-
           AikeVision.Limiter.run(
             AikeVision.Processes,
             fn -> tesseract(input, output, psm) end,
             :infinity
           ),
         {:ok, tsv} <- File.read(output <> ".tsv") do
      {:ok, parse(tsv)}
    else
      {:error, reason} when is_atom(reason) and reason != :enoent -> {:error, reason}
      _ -> {:error, :command_failed}
    end
  end

  defp tesseract(input, output, psm),
    do: Command.run("tesseract", [input, output, "-l", "por", "--psm", psm, "tsv"])

  @doc """
  Reads several images at the same time and keeps their order.

  ## Parameters
    - jobs: images, or `{image, psm}` tuples to choose the mode per image
    - directory: workspace for the temporary files
    - default_psm: mode for jobs given without one (default `"3"`)

  ## Returns
    - `{:ok, words_per_image}` in the order of `jobs`
    - the first `{:error, reason}` returned by `words/3`
  """
  @spec words_all([Evision.Mat.t() | {Evision.Mat.t(), String.t()}], Path.t(), String.t()) ::
          {:ok, [[word()]]} | {:error, Command.error() | :image_write_failed}
  def words_all(jobs, directory, default_psm \\ "3") do
    concurrency =
      Application.get_env(:aike_vision, :ocr_concurrency, System.schedulers_online())

    jobs
    |> Task.async_stream(
      fn
        {image, psm} -> words(image, directory, psm)
        image -> words(image, directory, default_psm)
      end,
      max_concurrency: concurrency,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, found}}, {:ok, all} -> {:cont, {:ok, [found | all]}}
      {:ok, error}, _ -> {:halt, error}
    end)
    |> then(fn
      {:ok, all} -> {:ok, Enum.reverse(all)}
      error -> error
    end)
  end

  @doc """
  Parses Tesseract TSV output into words.

  Rows without text or with a negative confidence (layout rows) are dropped.

  ## Parameters
    - tsv: the TSV text written by Tesseract

  ## Returns
    - the list of words, in reading order
  """
  @spec parse(String.t()) :: [word()]
  def parse(tsv) do
    case String.split(tsv, "\n", trim: true) do
      [header | rows] ->
        columns = String.split(header, "\t")
        Enum.flat_map(rows, &word(Enum.zip(columns, String.split(&1, "\t")) |> Map.new()))

      [] ->
        []
    end
  end

  defp word(%{"text" => text, "conf" => conf} = row) do
    with false <- String.trim(text) == "",
         {confidence, _} when confidence >= 0 <- Float.parse(conf),
         [left, top, width, height, block, par, line] <-
           integers(row, ~w(left top width height block_num par_num line_num)) do
      [
        %{
          text: text,
          confidence: confidence,
          box: {left, top, left + width, top + height},
          line: {block, par, line}
        }
      ]
    else
      _ -> []
    end
  end

  defp word(_), do: []

  defp integers(row, keys) do
    Enum.reduce_while(keys, [], fn key, values ->
      case Integer.parse(Map.get(row, key, "")) do
        {value, ""} -> {:cont, values ++ [value]}
        _ -> {:halt, nil}
      end
    end)
  end
end
