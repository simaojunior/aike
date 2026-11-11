defmodule DocumentClassifier.Engine.Tesseract do
  @moduledoc """
  Local OCR classifier: OpenCV preprocessing and the Tesseract executable, bounded in time.

  Reading is progressive: each stage adds OCR passes, cheapest and most telling first, and
  the rules run on everything read so far. A conclusive result (known type with acceptable
  quality; for an RG, both sides) skips the later stages, which saves CPU per document and
  raises the throughput of each node.

  - PDF: text layer and embedded images first; the page is rendered and read only when they
    leave the result open
  - Photo: turned upright and cropped (`AikeVision.Document`), so quality is measured on the
    document only; grayscale first, then the blue channel, then stretched contrast
    (`AikeVision.Image.stretch/1`) for faded ink on tinted paper, each only when needed
  - Admission: past the node's capacity (`AikeVision.Documents`), the request is refused at
    once instead of queueing work that would time out and hold memory

  ## Configuration

      config :document_classifier,
        engine: DocumentClassifier.Engine.Tesseract,
        engine_version: "tesseract-por-rules-4"

  ## Errors
    - `:invalid_request`: empty input
    - `:file_too_large`: more than 10 MB
    - `:unsupported_image`: not a JPEG, PNG or PDF, animated, or unreadable
    - `:image_too_large`: more than 20 megapixels
    - `:unsupported_page_count`: a PDF with more than one page
    - `:overloaded`: the node is at capacity (HTTP 503 with `Retry-After`)
    - `:service_unavailable`: a dependency failed or the 10 s deadline passed

  ## Examples

      {:ok, %{"document" => %{"type" => "rg", "side" => "single"}}} =
        DocumentClassifier.Engine.Tesseract.classify(bytes, [])
  """
  @behaviour DocumentClassifier.Engine
  alias AikeVision.{Document, Image, Pdf, Tesseract, Workspace}
  alias DocumentClassifier.Engine.TextRules
  require Logger

  @max_bytes 10_000_000
  @timeout_ms 10_000
  @ocr_size 2400
  @max_upscale 3
  @min_document_side 320
  @invalid [:unsupported_image, :image_too_large, :unsupported_page_count]

  @doc """
  Classifies a document image or PDF.

  ## Parameters
    - bytes: JPEG, PNG or single-page PDF, up to 10 MB
    - opts: unused

  ## Returns
    - `{:ok, result}` with `document`, `confidence` and `quality`
      (see `DocumentClassifier.Engine.TextRules`)
    - `{:error, reason}`, see the module errors
  """
  @impl true
  def classify(bytes, _opts)
      when is_binary(bytes) and byte_size(bytes) > 0 and byte_size(bytes) <= @max_bytes do
    wait = Application.get_env(:aike_vision, :admission_wait_ms, 3_000)
    work = fn -> Workspace.run(&extract(bytes, &1), @timeout_ms) end

    case AikeVision.Limiter.run(AikeVision.Documents, work, wait) do
      {:ok, result} ->
        {:ok, result}

      {:error, :overloaded} ->
        {:error, :overloaded}

      {:error, reason} when reason in @invalid ->
        {:error, reason}

      {:error, reason} ->
        unavailable(reason)
    end
  end

  def classify(bytes, _opts) when is_binary(bytes) and byte_size(bytes) > @max_bytes,
    do: {:error, :file_too_large}

  def classify(_, _), do: {:error, :invalid_request}

  defp extract(bytes, directory) do
    with {:ok, text_layer, stages, issues} <- prepare(bytes, directory) do
      read = &read_stage(&1, &2, {text_layer, issues, directory})

      case Enum.reduce_while(stages, {:ok, nil, []}, read) do
        {:ok, nil, _} -> {:ok, rules(text_layer, [], issues)}
        {:ok, result, _} -> {:ok, result}
        error -> error
      end
    end
  end

  defp read_stage(stage, {:ok, _, stages}, {text_layer, issues, directory}) do
    with {:ok, variants} <- stage.(),
         {:ok, found} <- Tesseract.words_all(variants, directory, "3") do
      stages = stages ++ found
      result = rules(text_layer, stages, issues)
      {step(conclusive?(result)), {:ok, result, stages}}
    else
      error -> {:halt, error}
    end
  end

  defp rules(text_layer, stages, issues) do
    TextRules.classify(
      Enum.join([text_layer | for(words <- stages, word <- words, do: word.text)], " "),
      quality_confidence(stages),
      issues
    )
  end

  @doc """
  The text confidence used for quality: the median word confidence of the best read.

  Weaker preparations read noise (guilloche, coat of arms) with low confidence; mixing
  them in would reject a document that one preparation reads well.

  ## Parameters
    - reads: the words of each OCR pass, one list per pass

  ## Returns
    - the highest per-pass median, from 0 to 100; 0 without words
  """
  @spec quality_confidence([[%{confidence: number()}]]) :: number()
  def quality_confidence(reads) do
    reads
    |> Enum.map(fn words -> median(Enum.map(words, & &1.confidence)) end)
    |> Enum.max(fn -> 0 end)
  end

  defp conclusive?(%{"document" => %{"type" => "cnh"}, "quality" => %{"acceptable" => true}}),
    do: true

  defp conclusive?(%{
         "document" => %{"type" => "rg", "side" => "single"},
         "quality" => %{"acceptable" => true}
       }),
       do: true

  defp conclusive?(_), do: false

  defp step(true), do: :halt
  defp step(false), do: :cont

  defp prepare(<<"%PDF-", _::binary>> = bytes, directory), do: prepare_pdf(bytes, directory)
  defp prepare(bytes, directory), do: prepare_photo(bytes, directory)

  defp prepare_pdf(bytes, directory) do
    path = Path.join(directory, "input.pdf")

    with :ok <- File.write(path, bytes),
         :ok <- Pdf.single_page(path),
         [{:ok, text_layer}, {:ok, embedded}] <-
           concurrently([
             fn -> Pdf.text_layer(path, directory) end,
             fn -> Pdf.embedded_images(path, directory) end
           ]) do
      {:ok, text_layer, pdf_stages(embedded, path, directory), []}
    end
  end

  defp pdf_stages([], path, directory), do: [fn -> render_page(path, directory) end]

  defp pdf_stages(embedded, path, directory),
    do: [fn -> gray_variants(embedded) end, fn -> render_page(path, directory) end]

  defp prepare_photo(bytes, directory) do
    with {:ok, image, header} <- Image.decode(bytes),
         {:ok, upright, legible} <- Document.orient(image, directory) do
      {document, issues} = crop_document(upright, Document.region(upright, legible))
      fitted = Image.fit(document, @max_upscale, @ocr_size, @ocr_size)

      {:ok, "", photo_stages(fitted, header.colored), issues}
    end
  end

  defp photo_stages(image, true),
    do: [
      fn -> {:ok, [Image.gray(image)]} end,
      fn -> {:ok, [Image.blue(image)]} end,
      fn -> {:ok, [image |> Image.gray() |> Image.stretch()]} end
    ]

  defp photo_stages(image, false),
    do: [
      fn -> {:ok, [Image.gray(image)]} end,
      fn -> {:ok, [image |> Image.gray() |> Image.stretch()]} end
    ]

  defp render_page(path, directory) do
    with {:ok, page} <- Pdf.render_page(path, directory, @ocr_size), do: gray_variants([page])
  end

  defp crop_document(image, nil), do: {image, ["document_not_detected"]}

  defp crop_document(image, box) do
    document = Image.crop(image, box)
    {width, height} = Image.size(document)
    {document, resolution_issues(min(width, height))}
  end

  defp resolution_issues(side) when side < @min_document_side, do: ["low_resolution"]
  defp resolution_issues(_side), do: []

  defp concurrently(steps) do
    steps
    |> Enum.map(&Task.async/1)
    |> Task.await_many(:infinity)
    |> then(fn results -> Enum.find(results, &match?({:error, _}, &1)) || results end)
  end

  defp gray_variants(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, images} ->
      case Image.read(path) do
        {:ok, image, _} ->
          {:cont,
           {:ok,
            images ++ [image |> Image.fit(@max_upscale, @ocr_size, @ocr_size) |> Image.gray()]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp median([]), do: 0

  defp median(values) do
    sorted = Enum.sort(values)
    middle(sorted, length(sorted))
  end

  defp middle(sorted, count) when rem(count, 2) == 1, do: Enum.at(sorted, div(count, 2))

  defp middle(sorted, count),
    do: (Enum.at(sorted, div(count, 2) - 1) + Enum.at(sorted, div(count, 2))) / 2

  defp unavailable(reason) do
    Logger.error("Tesseract extraction failed: #{reason}", event: "classifier.ocr.failed")
    {:error, :service_unavailable}
  end
end
