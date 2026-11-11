defmodule AikeVision.Image do
  @moduledoc """
  OpenCV image operations used before OCR.

  Images are BGR `Evision.Mat` values. Decoding checks the header first
  (`AikeVision.ImageHeader`) and applies the EXIF orientation, so photos arrive as the
  camera saw them. Upscaling uses bicubic interpolation: Lanczos sharpens edges and made
  Tesseract misread letters ("PERREIRA" for "FERREIRA").

  ## Examples

      {:ok, image, header} = AikeVision.Image.decode(bytes)
      gray = image |> AikeVision.Image.fit(3, 2400, 2400) |> AikeVision.Image.gray()
  """
  alias AikeVision.ImageHeader
  alias Evision.Constant, as: CV

  @paper_percentile 0.75
  @ink_depth 70

  @type box :: {number(), number(), number(), number()}

  @doc """
  Decodes a JPEG or PNG after checking its header.

  A JPEG above 20 million pixels is decoded at the reduction in `header.scale`, so the
  returned image is smaller than the original; the header keeps the original size.

  ## Parameters
    - bytes: the complete image file

  ## Returns
    - `{:ok, image, header}` with the BGR image and its `AikeVision.ImageHeader`
    - `{:error, :unsupported_image | :image_too_large}`

  ## Example

      {:ok, image, %{colored: true}} = AikeVision.Image.decode(File.read!("card.jpg"))
  """
  @spec decode(binary()) ::
          {:ok, Evision.Mat.t(), ImageHeader.t()}
          | {:error, :unsupported_image | :image_too_large}
  def decode(bytes) do
    with {:ok, header} <- ImageHeader.read(bytes) do
      case Evision.imdecode(bytes, flag(header.scale)) do
        %Evision.Mat{} = image -> {:ok, image, header}
        _ -> {:error, :unsupported_image}
      end
    end
  end

  defp flag(1), do: CV.cv_IMREAD_COLOR()
  defp flag(2), do: CV.cv_IMREAD_REDUCED_COLOR_2()
  defp flag(4), do: CV.cv_IMREAD_REDUCED_COLOR_4()
  defp flag(8), do: CV.cv_IMREAD_REDUCED_COLOR_8()

  @doc """
  Reads and decodes an image file.

  ## Parameters
    - path: path of a JPEG or PNG file

  ## Returns
    - `{:ok, image, header}`
    - `{:error, :unsupported_image | :image_too_large}`, also when the file cannot be read
  """
  @spec read(Path.t()) ::
          {:ok, Evision.Mat.t(), ImageHeader.t()}
          | {:error, :unsupported_image | :image_too_large}
  def read(path) do
    case File.read(path) do
      {:ok, bytes} -> decode(bytes)
      _ -> {:error, :unsupported_image}
    end
  end

  @doc """
  Width and height of an image, in pixels.

  ## Parameters
    - image: a grayscale or color image

  ## Returns
    - `{width, height}`
  """
  @spec size(Evision.Mat.t()) :: {pos_integer(), pos_integer()}
  def size(%Evision.Mat{shape: {height, width}}), do: {width, height}
  def size(%Evision.Mat{shape: {height, width, _}}), do: {width, height}

  @doc """
  Rotations to try when looking for the upright orientation.

  The order is fixed (as given, 90° counterclockwise, 180°, 90° clockwise), so a tie
  always picks the same rotation.

  ## Returns
    - a list of rotation codes for `rotate/2`; `nil` keeps the image as given
  """
  @spec rotations() :: [nil | integer()]
  def rotations,
    do: [nil, CV.cv_ROTATE_90_COUNTERCLOCKWISE(), CV.cv_ROTATE_180(), CV.cv_ROTATE_90_CLOCKWISE()]

  @doc """
  Rotates an image by a code from `rotations/0`.

  ## Parameters
    - image: the image
    - code: an OpenCV rotation code, or `nil` to keep the image

  ## Returns
    - the rotated image
  """
  @spec rotate(Evision.Mat.t(), nil | integer()) :: Evision.Mat.t()
  def rotate(image, nil), do: image
  def rotate(image, code), do: Evision.rotate(image, code)

  @doc """
  Scales an image down so its longest side is at most `max_side`. Never scales up.

  ## Parameters
    - image: the image
    - max_side: the longest side allowed, in pixels

  ## Returns
    - the image, smaller or unchanged
  """
  @spec shrink(Evision.Mat.t(), pos_integer()) :: Evision.Mat.t()
  def shrink(image, max_side) do
    {width, height} = size(image)
    scale_down(image, max_side / max(width, height))
  end

  @doc """
  Scales an image up for OCR, then caps its size.

  Small text needs more pixels per letter to be read. The image grows until its longest
  side reaches `target`, by at most `max_upscale` times, and never passes `max_side`.

  ## Parameters
    - image: the image
    - max_upscale: the largest scale factor
    - target: the longest side to reach, in pixels
    - max_side: the longest side allowed, in pixels

  ## Returns
    - the scaled image

  ## Example

      AikeVision.Image.fit(card, 4, 2000, 2400)
  """
  @spec fit(Evision.Mat.t(), number(), pos_integer(), pos_integer()) :: Evision.Mat.t()
  def fit(image, max_upscale, target, max_side) do
    {width, height} = size(image)
    factor = min(max_upscale, target / max(width, height))

    image |> scale_up(factor) |> shrink(max_side)
  end

  @doc """
  Converts a BGR image to grayscale.

  ## Parameters
    - image: a BGR image

  ## Returns
    - a single-channel image
  """
  @spec gray(Evision.Mat.t()) :: Evision.Mat.t()
  def gray(image), do: Evision.cvtColor(image, CV.cv_COLOR_BGR2GRAY())

  @doc """
  Extracts the blue channel of a BGR image.

  Brazilian documents print on green or blue security paper; the blue channel separates
  the dark ink from the paper better than grayscale.

  ## Parameters
    - image: a BGR image

  ## Returns
    - a single-channel image
  """
  @spec blue(Evision.Mat.t()) :: Evision.Mat.t()
  def blue(image), do: Evision.extractChannel(image, 0)

  @doc """
  Stretches the contrast of a grayscale image between the paper and light ink.

  The paper brightness is the 75th percentile of the image. Pixels at least 70 levels
  darker than the paper become black, and pixels at the paper level become white. Light ink,
  such as the red values of a CNH on green paper, then reaches the contrast Tesseract
  needs.

  ## Parameters
    - gray: a single-channel image

  ## Returns
    - a single-channel image of the same size
  """
  @spec stretch(Evision.Mat.t()) :: Evision.Mat.t()
  def stretch(gray) do
    paper = percentile(gray, @paper_percentile)
    low = max(paper - @ink_depth, 0)
    high = max(paper, low + 1)

    gray
    |> Evision.subtract({low / 1})
    |> Evision.multiply({255 / (high - low)})
  end

  defp percentile(gray, fraction) do
    counts =
      [gray]
      |> Evision.calcHist([0], Evision.Mat.empty(), [256], [0, 256])
      |> Evision.Mat.to_nx(Nx.BinaryBackend)
      |> Nx.flatten()
      |> Nx.cumulative_sum()
      |> Nx.to_flat_list()

    total = List.last(counts)
    Enum.find_index(counts, &(&1 >= total * fraction)) || 255
  end

  @doc """
  Cuts a rectangle out of an image.

  ## Parameters
    - image: the image
    - box: `{left, top, right, bottom}` in pixels

  ## Returns
    - the cropped image
  """
  @spec crop(Evision.Mat.t(), box()) :: Evision.Mat.t()
  def crop(image, {left, top, right, bottom}) do
    {x, y} = {round(left), round(top)}
    Evision.Mat.roi(image, {x, y, round(right) - x, round(bottom) - y})
  end

  @doc """
  Writes an image to a file; the format follows the file extension.

  ## Parameters
    - image: the image
    - path: destination path, such as `ocr-1.png`

  ## Returns
    - `:ok`
    - `{:error, :image_write_failed}`
  """
  @spec write(Evision.Mat.t(), Path.t()) :: :ok | {:error, :image_write_failed}
  def write(image, path) do
    case Evision.imwrite(path, image) do
      true -> :ok
      _ -> {:error, :image_write_failed}
    end
  end

  defp scale_down(image, factor) when factor < 1, do: resize(image, factor, CV.cv_INTER_AREA())
  defp scale_down(image, _factor), do: image

  defp scale_up(image, factor) when factor > 1, do: resize(image, factor, CV.cv_INTER_CUBIC())
  defp scale_up(image, _factor), do: image

  defp resize(image, factor, interpolation) do
    {width, height} = size(image)

    Evision.resize(image, {max(1, round(width * factor)), max(1, round(height * factor))},
      interpolation: interpolation
    )
  end
end
