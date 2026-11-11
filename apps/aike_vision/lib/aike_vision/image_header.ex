defmodule AikeVision.ImageHeader do
  @moduledoc """
  Format and dimensions of a JPEG or PNG, read from its header without decoding pixels.

  Checking the pixel count before decoding stops decompression bombs: small files that
  expand to images too large for memory. A JPEG above 20 million pixels is not refused:
  `scale` tells the decoder to read it at 1/2, 1/4 or 1/8 of its size, the smallest
  reduction that fits, so a 48 MP phone photo never loads whole. A PNG has no reduced
  decoding and stays limited to 20 million pixels. Animated PNGs are refused, because a
  document is a single frame.

  ## Properties
    - `format`: `:jpeg` or `:png`
    - `width` / `height`: size in pixels
    - `colored`: the image has color channels
    - `bilevel`: a 1-bit black and white PNG, such as a QR code mask
    - `scale`: 1, 2, 4 or 8; the image is decoded at `1/scale` of its size

  ## Errors
    - `:unsupported_image`: not a JPEG or PNG, animated, or zero-sized
    - `:image_too_large`: a PNG above 20 million pixels, or a JPEG still above it at 1/8

  ## Examples

      {:ok, %{format: :jpeg, width: 1200, height: 1600}} = AikeVision.ImageHeader.read(bytes)
  """

  @type t :: %{
          format: :jpeg | :png,
          width: pos_integer(),
          height: pos_integer(),
          colored: boolean(),
          bilevel: boolean(),
          scale: 1 | 2 | 4 | 8
        }

  @max_pixels 20_000_000
  @png_signature <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>

  @doc """
  Reads the header of `bytes`.

  ## Parameters
    - bytes: the complete image file

  ## Returns
    - `{:ok, header}` with format, size and color information
    - `{:error, :unsupported_image | :image_too_large}`

  ## Example

      {:error, :image_too_large} = AikeVision.ImageHeader.read(huge_png)
  """
  @spec read(binary()) :: {:ok, t()} | {:error, :unsupported_image | :image_too_large}
  def read(bytes) when is_binary(bytes) do
    with {:ok, header} <- parse(bytes),
         true <- (header.width > 0 and header.height > 0) or {:error, :unsupported_image},
         {:ok, scale} <- scale(header.format, header.width * header.height) do
      {:ok, Map.put(header, :scale, scale)}
    end
  end

  defp scale(_format, pixels) when pixels <= @max_pixels, do: {:ok, 1}

  defp scale(:jpeg, pixels) do
    case Enum.find([2, 4, 8], &(pixels / (&1 * &1) <= @max_pixels)) do
      nil -> {:error, :image_too_large}
      scale -> {:ok, scale}
    end
  end

  defp scale(_format, _pixels), do: {:error, :image_too_large}

  defp parse(
         <<@png_signature, _length::32, "IHDR", width::32, height::32, depth, color_type,
           _::binary>> = bytes
       ) do
    png(:binary.match(bytes, "acTL"), width, height, depth, color_type)
  end

  defp parse(<<0xFF, 0xD8, rest::binary>>), do: jpeg_frame(rest)
  defp parse(_), do: {:error, :unsupported_image}

  defp png(:nomatch, width, height, depth, color_type) do
    {:ok,
     %{
       format: :png,
       width: width,
       height: height,
       colored: color_type in [2, 3, 6],
       bilevel: depth == 1 and color_type == 0
     }}
  end

  defp png(_animation_control, _width, _height, _depth, _color_type),
    do: {:error, :unsupported_image}

  defp jpeg_frame(<<0xFF, 0xFF, rest::binary>>), do: jpeg_frame(<<0xFF, rest::binary>>)

  defp jpeg_frame(
         <<0xFF, marker, _length::16, _precision, height::16, width::16, components, _::binary>>
       )
       when marker in 0xC0..0xCF and marker not in [0xC4, 0xC8, 0xCC] do
    {:ok,
     %{format: :jpeg, width: width, height: height, colored: components >= 3, bilevel: false}}
  end

  defp jpeg_frame(<<0xFF, marker, rest::binary>>) when marker in 0xD0..0xD7 or marker == 0x01,
    do: jpeg_frame(rest)

  defp jpeg_frame(<<0xFF, _marker, length::16, rest::binary>>)
       when length >= 2 and byte_size(rest) >= length - 2 do
    jpeg_frame(binary_part(rest, length - 2, byte_size(rest) - (length - 2)))
  end

  defp jpeg_frame(_), do: {:error, :unsupported_image}
end
