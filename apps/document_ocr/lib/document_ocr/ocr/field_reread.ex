defmodule DocumentOcr.OCR.FieldReread do
  @moduledoc """
  Reads again, from a crop, short values that full-page passes miss.

  A short isolated value, such as the CNH category ("AB"), often has too little context for
  a full-page pass. For every target label found in the lines of an image, the area just
  below the label is cut, enlarged and read in grayscale as a single line (`--psm 7`).
  In a small crop, Tesseract's own threshold separates light ink from the paper.

  The result goes to a source of its own (`"<image>.r<label>"`) with a copy of the label
  line, so the extractor finds it below the label like any other pass. It is one more
  vote, never a replacement for the other passes.

  ## Properties
    - Targets on the CNH (and on automatic detection): category (`CAT HAB`), expiration
      (`VALIDADE`) and registration number (`REGISTRO`), all printed in light red
    - Area: from the label's bottom down 2.5 label heights. Each target sets how far the
      area starts left of the label (in label heights; "Nº" sits left of "REGISTRO") and
      how wide it is (in label widths; dates and numbers are wider than their labels)

  ## Examples

      extra_lines = DocumentOcr.OCR.FieldReread.lines(image, image_lines, 0, "cnh", directory)
  """
  alias AikeVision.{Image, Tesseract}
  alias DocumentOcr.Extraction.Layout

  @cnh_targets [
    {"CAT HAB", 0.5, 1.0},
    {"VALIDADE", 0.5, 2.0},
    {"REGISTRO", 2.5, 2.3}
  ]
  @targets %{"cnh" => @cnh_targets, "auto" => @cnh_targets}
  @right_margin 0.5
  @depth 2.5
  @upscale 2
  @max_side 1200

  @doc """
  Reads the target fields of one image again.

  ## Parameters
    - image: the fitted color image that the passes read
    - lines: the lines read from that image, with words
    - index: the index of the image in the document
    - document_type: `"cnh"`, `"rg"` or `"auto"`
    - directory: private workspace for temporary files

  ## Returns
    - `{:ok, lines}`: a copy of each label line and the value read below it; `[]` when no
      target label was found
    - `{:error, reason}` when Tesseract fails
  """
  @spec lines(Evision.Mat.t(), [map()], non_neg_integer(), String.t() | nil, Path.t()) ::
          {:ok, [map()]} | {:error, term()}
  def lines(image, lines, index, document_type, directory) do
    @targets
    |> Map.get(document_type, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {target, number} ->
      first_label(lines, target, "#{index}.r#{number}")
    end)
    |> Enum.reduce_while({:ok, []}, fn target, {:ok, acc} ->
      case reread(image, target, directory) do
        {:ok, found} -> {:cont, {:ok, acc ++ found}}
        error -> {:halt, error}
      end
    end)
  end

  defp first_label(lines, {label, left_heights, widths}, source) do
    case Layout.find(lines, label) do
      [found | _] -> [Map.merge(found, %{reread_source: source, extent: {left_heights, widths}})]
      [] -> []
    end
  end

  defp reread(image, %{line: line, box: box, reread_source: source, extent: extent}, directory) do
    {width, height} = Image.size(image)
    {left, top, right, bottom} = area(box, extent, width, height)

    region = Image.crop(image, {left, top, right, bottom})
    {region_width, _} = Image.size(region)
    fitted = Image.fit(region, @upscale, @max_side, @max_side)
    {fitted_width, _} = Image.size(fitted)
    scale = fitted_width / region_width

    with {:ok, words} <- Tesseract.words(Image.gray(fitted), directory, "7") do
      label_line = Map.put(line, "source", source)
      {:ok, [label_line | value_line(words, {left, top}, scale, source)]}
    end
  end

  defp area([left, top, width, height], {left_heights, widths}, image_width, image_height) do
    area_top = min(top + height, image_height - 1)
    area_left = max(round(left - height * left_heights), 0)
    area_right = min(round(left + width * widths + height * @right_margin), image_width)

    {area_left, area_top, max(area_right, area_left + 1),
     min(round(area_top + height * @depth), image_height)}
  end

  defp value_line([], _origin, _scale, _source), do: []

  defp value_line(words, {left, top}, scale, source) do
    placed =
      Enum.map(words, fn %{box: {word_left, word_top, word_right, word_bottom}} = word ->
        %{
          "text" => word.text,
          "confidence" => Float.round(word.confidence / 100, 4),
          "bbox" => [
            round(left + word_left / scale),
            round(top + word_top / scale),
            max(round((word_right - word_left) / scale), 1),
            max(round((word_bottom - word_top) / scale), 1)
          ]
        }
      end)

    [
      %{
        "text" => Enum.map_join(placed, " ", & &1["text"]),
        "confidence" => Layout.mean_confidence(placed),
        "bbox" => union(Enum.map(placed, & &1["bbox"])),
        "source" => source,
        "words" => placed
      }
    ]
  end

  defp union(boxes) do
    left = boxes |> Enum.map(fn [l, _, _, _] -> l end) |> Enum.min()
    top = boxes |> Enum.map(fn [_, t, _, _] -> t end) |> Enum.min()
    right = boxes |> Enum.map(fn [l, _, w, _] -> l + w end) |> Enum.max()
    bottom = boxes |> Enum.map(fn [_, t, _, h] -> t + h end) |> Enum.max()
    [left, top, right - left, bottom - top]
  end
end
