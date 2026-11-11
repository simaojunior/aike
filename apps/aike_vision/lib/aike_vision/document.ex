defmodule AikeVision.Document do
  @moduledoc """
  Finds how a photographed document is turned and where it sits in the photo.

  Orientation: Tesseract reads only horizontal text, so the photo is read as given first.
  When it shows fewer than eight confident horizontal words, the other three rotations are
  read in parallel and the one with most words wins. Only words wider than tall count,
  because Tesseract also reads vertical lines and a sideways rotation could otherwise score
  as many words. When no rotation shows three words, the four rotations are read again
  with stretched contrast (`AikeVision.Image.stretch/1`): faded ink on tinted paper, such as
  an old RG on a dark table, disappears in plain grayscale.

  Region: the paper color is the median color around the legible words. The region is the
  paper-colored area connected to those words, with its holes filled, cut to its densest
  rectangle (a projection profile drops thin attachments such as glare on the table) and
  padded by 7%. Filling the holes keeps white photo and fingerprint boxes inside the card:
  on some RGs they cover half of it.

  ## Examples

      {:ok, upright, legible} = AikeVision.Document.orient(image, directory)
      box = AikeVision.Document.region(upright, legible)
  """
  alias AikeVision.{Image, Tesseract}
  alias Evision.Constant, as: CV

  @orientation_size 1200
  @upright_words 8
  @detection_size 320
  @min_legible_words 3
  @paper_color_distance 45
  @dense_fraction 0.4
  @region_padding 0.07
  @min_region_area 0.05

  @doc """
  Turns a photo upright.

  ## Parameters
    - image: the decoded photo
    - directory: workspace for the OCR files

  ## Returns
    - `{:ok, upright_image, legible_boxes}`: the boxes of the confident words, used by
      `region/2`
    - `{:error, reason}` from `AikeVision.Tesseract`
  """
  @spec orient(Evision.Mat.t(), Path.t()) ::
          {:ok, Evision.Mat.t(), [Image.box()]} | {:error, term()}
  def orient(image, directory) do
    [as_given | turned] = Image.rotations()

    with {:ok, [first]} <- read_rotations(image, [as_given], directory, &Image.gray/1) do
      upright_or_turned(first, image, turned, directory)
    end
  end

  defp upright_or_turned({upright, legible}, _image, _turned, _directory)
       when length(legible) >= @upright_words,
       do: {:ok, upright, legible}

  defp upright_or_turned(first, image, turned, directory) do
    with {:ok, others} <- read_rotations(image, turned, directory, &Image.gray/1) do
      [first | others] |> Enum.reduce(&most_legible/2) |> faded_or_found(image, directory)
    end
  end

  defp faded_or_found({_, legible} = found, _image, _directory)
       when length(legible) >= @min_legible_words,
       do: {:ok, elem(found, 0), legible}

  defp faded_or_found(found, image, directory) do
    with {:ok, stretched} <- read_rotations(image, Image.rotations(), directory, &stretched/1) do
      {upright, legible} = Enum.reduce(stretched, found, &most_legible/2)
      {:ok, upright, legible}
    end
  end

  defp stretched(image), do: image |> Image.gray() |> Image.stretch()

  defp read_rotations(image, rotations, directory, prepare) do
    rotated = Enum.map(rotations, &Image.rotate(image, &1))
    samples = Enum.map(rotated, &(&1 |> Image.shrink(@orientation_size) |> prepare.()))

    with {:ok, words} <- Tesseract.words_all(samples, directory, "3") do
      {:ok,
       Enum.zip_with([rotated, samples, words], fn [full, sample, found] ->
         {full, legible(full, sample, found)}
       end)}
    end
  end

  defp most_legible({_, candidate} = next, {_, best}) when length(candidate) > length(best),
    do: next

  defp most_legible(_next, current), do: current

  defp legible(full, sample, words) do
    {width, _} = Image.size(full)
    {sample_width, _} = Image.size(sample)

    for %{text: text, confidence: confidence, box: {left, top, right, bottom} = box} <- words,
        confidence >= 80 and String.length(text) >= 4 and right - left > bottom - top,
        do: scale_box(box, width / sample_width)
  end

  @doc """
  Finds the document inside an upright photo.

  ## Parameters
    - image: the upright photo
    - legible: word boxes returned by `orient/2`

  ## Returns
    - `{left, top, right, bottom}` of the document
    - `nil` when there are fewer than three legible words or the region is under 5% of
      the photo
  """
  @spec region(Evision.Mat.t(), [Image.box()]) :: Image.box() | nil
  def region(_image, legible) when length(legible) < @min_legible_words, do: nil

  def region(image, legible) do
    {width, height} = Image.size(image)
    sample = Image.shrink(image, @detection_size)
    {sample_width, sample_height} = Image.size(sample)
    scale = sample_width / width
    seed = legible |> union() |> scale_box(scale) |> clamp(sample_width, sample_height)

    with {left, top, right, bottom} when right > left and bottom > top <- seed,
         {:ok, rows} <- paper_rows(sample, seed) do
      {top, bottom} = dense_run(Enum.map(rows, &Enum.sum/1), top, bottom)

      {left, right} =
        rows
        |> Enum.slice(top..(bottom - 1))
        |> Enum.zip_with(&Enum.sum/1)
        |> dense_run(left, right)

      {pad_x, pad_y} = {(right - left) * @region_padding, (bottom - top) * @region_padding}

      box =
        {max(0, (left - pad_x) / scale), max(0, (top - pad_y) / scale),
         min(width, (right + pad_x) / scale), min(height, (bottom + pad_y) / scale)}

      large_enough(box, area(box), @min_region_area * width * height)
    else
      _ -> nil
    end
  end

  defp paper_rows(sample, {left, top, right, bottom} = seed) do
    {width, height} = Image.size(sample)
    paper = sample |> Image.crop(seed) |> Evision.split() |> Enum.map(&median/1)
    channels = Enum.map(paper, &Evision.Mat.full({height, width}, &1, {:f, 32}))
    difference = Evision.subtract(Evision.Mat.as_type(sample, {:f, 32}), Evision.merge(channels))
    [blue, green, red] = Evision.split(Evision.multiply(difference, difference))
    squared_distance = Evision.add(Evision.add(blue, green), red)

    {_, mask} =
      Evision.threshold(
        squared_distance,
        @paper_color_distance ** 2,
        255,
        CV.cv_THRESH_BINARY_INV()
      )

    kernel = Evision.getStructuringElement(CV.cv_MORPH_RECT(), {5, 5})
    closed = Evision.morphologyEx(Evision.Mat.as_type(mask, {:u, 8}), CV.cv_MORPH_CLOSE(), kernel)
    {_count, labels} = Evision.connectedComponents(closed, connectivity: 4, ltype: CV.cv_32S())

    rows =
      for(<<label::little-signed-32 <- Evision.Mat.to_binary(labels)>>, do: label)
      |> Enum.chunk_every(width)

    seeded =
      rows
      |> Enum.slice(top..(bottom - 1))
      |> Enum.flat_map(&Enum.slice(&1, left..(right - 1)))
      |> MapSet.new()
      |> MapSet.delete(0)

    flags(MapSet.size(seeded), rows, seeded, {width, height})
  end

  defp large_enough(box, area, minimum) when area >= minimum, do: box
  defp large_enough(_box, _area, _minimum), do: nil

  defp flags(0, _rows, _seeded, _size), do: :error

  defp flags(_count, rows, seeded, {width, height}) do
    component =
      for(row <- rows, label <- row, into: <<>>, do: <<pixel(label in seeded)>>)
      |> Evision.Mat.from_binary({:u, 8}, height, width, 1)

    {contours, _hierarchy} =
      Evision.findContours(component, CV.cv_RETR_EXTERNAL(), CV.cv_CHAIN_APPROX_SIMPLE())

    filled =
      {height, width}
      |> Evision.Mat.zeros({:u, 8})
      |> Evision.drawContours(contours, -1, {255}, thickness: -1)

    {:ok,
     filled
     |> Evision.Mat.to_binary()
     |> :binary.bin_to_list()
     |> Enum.map(&min(&1, 1))
     |> Enum.chunk_every(width)}
  end

  defp pixel(true), do: 255
  defp pixel(false), do: 0

  defp median(channel) do
    bytes = Evision.Mat.to_binary(channel)
    counts = bytes |> :binary.bin_to_list() |> Enum.frequencies()
    half = byte_size(bytes) / 2

    Enum.reduce_while(0..255, 0, fn value, seen ->
      median_step(seen + Map.get(counts, value, 0), half, value)
    end)
  end

  defp median_step(seen, half, value) when seen >= half, do: {:halt, value}
  defp median_step(seen, _half, _value), do: {:cont, seen}

  defp dense_run(counts, start, finish) do
    limit = Enum.max(counts) * @dense_fraction
    tuple = List.to_tuple(counts)
    start = extend(start, -1, tuple, limit)
    finish = extend(finish - 1, 1, tuple, limit) + 1
    {start, finish}
  end

  defp extend(index, step, counts, limit), do: extend(index, index + step, step, counts, limit)

  defp extend(_index, next, step, counts, limit)
       when next >= 0 and next < tuple_size(counts) and elem(counts, next) >= limit,
       do: extend(next, step, counts, limit)

  defp extend(index, _next, _step, _counts, _limit), do: index

  defp union(boxes) do
    {lefts, tops, rights, bottoms} =
      Enum.reduce(boxes, {[], [], [], []}, fn {l, t, r, b}, {ls, ts, rs, bs} ->
        {[l | ls], [t | ts], [r | rs], [b | bs]}
      end)

    {Enum.min(lefts), Enum.min(tops), Enum.max(rights), Enum.max(bottoms)}
  end

  defp scale_box({left, top, right, bottom}, factor),
    do: {left * factor, top * factor, right * factor, bottom * factor}

  defp clamp({left, top, right, bottom}, width, height),
    do:
      {max(0, round(left)), max(0, round(top)), min(width, round(right)),
       min(height, round(bottom))}

  defp area({left, top, right, bottom}), do: (right - left) * (bottom - top)
end
