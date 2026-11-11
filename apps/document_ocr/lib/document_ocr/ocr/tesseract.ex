defmodule DocumentOcr.OCR.Tesseract do
  @moduledoc """
  Local OCR engine: OpenCV preprocessing and the Tesseract executable, bounded in time.

  Returns text lines, with the box of every word, for the label extractors.

  - PDF: the embedded images at their native resolution; the rendered page only when the
    PDF has no usable image
  - Photo: turned upright and cropped to the document (`AikeVision.Document`). An open
    booklet wider than 2.2:1 (an RG with front and back side by side) is read as two halves,
    so lines do not join across halves and each half can be upscaled more
  - Passes: grayscale, blue channel and stretched grayscale (`AikeVision.Image.stretch/1`)
    with `--psm 4`; the stretched pass reads light ink, such as the red values of a CNH.
    RGs (and unknown types) get one more sparse pass (`--psm 11`) on the blue channel for
    isolated fields such as the birth date. Every pass is a separate source,
    `"<image>.<pass>"`; passes of one image share coordinates
  - Short values that passes miss (the CNH category) are read again from a crop below their
    label (`DocumentOcr.OCR.FieldReread`)

  ## Configuration

      config :document_ocr,
        ocr_engine: DocumentOcr.OCR.Tesseract,
        ocr_engine_version: "tesseract-5-por-5"

  ## Errors
    - `:unsupported_engine_version`: the document was pinned to another version
    - `:invalid_image`: empty, too large, unsupported or multi-page input
    - `{:unavailable, reason}`: a dependency failed or the 12 s deadline passed

  ## Examples

      {:ok, %{"text" => lines}} =
        DocumentOcr.OCR.Tesseract.extract(bytes,
          engine_version: "tesseract-5-por-5",
          document_type: "rg"
        )
  """
  @behaviour DocumentOcr.OCR.Engine
  alias AikeVision.{Document, Image, Pdf, Tesseract, Workspace}
  alias DocumentOcr.OCR.FieldReread
  require Logger

  @version "tesseract-5-por-5"
  @max_bytes 10_000_000
  @timeout_ms 12_000
  @ocr_size 2400
  @target_size 2000
  @max_upscale 4
  @spread_ratio 2.2
  @invalid [:unsupported_image, :image_too_large, :unsupported_page_count]

  @doc """
  The engine version this module implements.

  ## Returns
    - the version string registered in `config/config.exs`
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Reads the text lines of a document.

  ## Parameters
    - bytes: JPEG, PNG or single-page PDF, up to 10 MB
    - opts: `:engine_version` (must match `version/0`), `:document_type` (`"cnh"`,
      `"rg"` or `"auto"`)

  ## Returns
    - `{:ok, %{"text" => lines}}`: each line with `text`, `confidence` (0 to 1), `bbox`,
      `source` and `words`
    - `{:error, reason}`, see the module errors
  """
  @impl true
  def extract(bytes, opts) do
    cond do
      Keyword.get(opts, :engine_version) != @version -> {:error, :unsupported_engine_version}
      not is_binary(bytes) or byte_size(bytes) == 0 -> {:error, :invalid_image}
      byte_size(bytes) > @max_bytes -> {:error, :invalid_image}
      true -> bounded(bytes, Keyword.get(opts, :document_type))
    end
  end

  defp bounded(bytes, document_type) do
    case Workspace.run(&read_lines(bytes, document_type, &1), @timeout_ms) do
      {:ok, lines} -> {:ok, %{"text" => lines}}
      {:error, reason} when reason in @invalid -> {:error, :invalid_image}
      {:error, reason} -> unavailable(reason)
    end
  end

  defp read_lines(bytes, document_type, directory) do
    with {:ok, images} <- images(bytes, directory),
         fitted = Enum.map(images, &fit/1),
         jobs = Enum.map(fitted, fn {image, colored} -> passes(image, colored, document_type) end),
         {:ok, words} <- Tesseract.words_all(List.flatten(jobs), directory),
         lines =
           words
           |> Enum.zip(sources(jobs))
           |> Enum.flat_map(fn {found, source} -> group(found, source) end),
         {:ok, reread} <- reread(fitted, lines, document_type, directory) do
      {:ok, lines ++ reread}
    end
  end

  defp sources(jobs) do
    for {passes, image} <- Enum.with_index(jobs),
        {_pass, pass} <- Enum.with_index(passes),
        do: "#{image}.#{pass}"
  end

  defp fit({image, colored}),
    do: {Image.fit(image, @max_upscale, @target_size, @ocr_size), colored}

  defp reread(fitted, lines, document_type, directory) do
    fitted
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{image, _}, index}, {:ok, acc} ->
      image_lines = Enum.filter(lines, &String.starts_with?(&1["source"], "#{index}."))

      case FieldReread.lines(image, image_lines, index, document_type, directory) do
        {:ok, found} -> {:cont, {:ok, acc ++ found}}
        error -> {:halt, error}
      end
    end)
  end

  defp images(<<"%PDF-", _::binary>> = bytes, directory) do
    path = Path.join(directory, "input.pdf")

    with :ok <- File.write(path, bytes),
         :ok <- Pdf.single_page(path),
         {:ok, paths} <- pdf_images(path, directory) do
      read_all(paths)
    end
  end

  defp images(bytes, directory) do
    with {:ok, image, header} <- Image.decode(bytes),
         {:ok, upright, legible} <- Document.orient(image, directory) do
      document = crop(upright, Document.region(upright, legible))
      {:ok, Enum.map(halves(document), &{&1, header.colored})}
    end
  end

  defp crop(image, nil), do: image
  defp crop(image, box), do: Image.crop(image, box)

  defp halves(image) do
    {width, height} = Image.size(image)
    split(image, width, height)
  end

  defp split(image, width, height) when width / height >= @spread_ratio do
    middle = div(width, 2)
    [Image.crop(image, {0, 0, middle, height}), Image.crop(image, {middle, 0, width, height})]
  end

  defp split(image, _width, _height), do: [image]

  defp pdf_images(path, directory) do
    case Pdf.embedded_images(path, directory) do
      {:ok, []} ->
        with {:ok, page} <- Pdf.render_page(path, directory, @ocr_size), do: {:ok, [page]}

      other ->
        other
    end
  end

  defp read_all(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, images} ->
      case Image.read(path) do
        {:ok, image, header} -> {:cont, {:ok, images ++ [{image, header.colored}]}}
        error -> {:halt, error}
      end
    end)
  end

  defp passes(fitted, colored, document_type) do
    cond do
      not colored ->
        [{Image.gray(fitted), "4"}]

      document_type in ["rg", "auto"] ->
        [
          {Image.gray(fitted), "4"},
          {Image.blue(fitted), "4"},
          {Image.blue(fitted), "11"},
          {Image.stretch(Image.gray(fitted)), "4"}
        ]

      true ->
        [
          {Image.gray(fitted), "4"},
          {Image.blue(fitted), "4"},
          {Image.stretch(Image.gray(fitted)), "4"}
        ]
    end
  end

  defp group(words, source) do
    words
    |> Enum.chunk_by(& &1.line)
    |> Enum.map(fn line_words ->
      {lefts, tops, rights, bottoms} = edges(line_words)
      left = Enum.min(lefts)
      top = Enum.min(tops)

      %{
        "text" => Enum.map_join(line_words, " ", & &1.text),
        "confidence" =>
          Float.round(
            Enum.sum(Enum.map(line_words, & &1.confidence)) / length(line_words) / 100,
            4
          ),
        "bbox" => [left, top, Enum.max(rights) - left, Enum.max(bottoms) - top],
        "source" => source,
        "words" => Enum.map(line_words, &word/1)
      }
    end)
  end

  defp word(%{text: text, confidence: confidence, box: {left, top, right, bottom}}),
    do: %{
      "text" => text,
      "confidence" => Float.round(confidence / 100, 4),
      "bbox" => [left, top, right - left, bottom - top]
    }

  defp edges(words) do
    Enum.reduce(words, {[], [], [], []}, fn %{box: {l, t, r, b}}, {ls, ts, rs, bs} ->
      {[l | ls], [t | ts], [r | rs], [b | bs]}
    end)
  end

  defp unavailable(reason) do
    Logger.error("Tesseract OCR failed: #{reason}", event: "ocr.tesseract.failed")
    {:error, {:unavailable, reason}}
  end
end
