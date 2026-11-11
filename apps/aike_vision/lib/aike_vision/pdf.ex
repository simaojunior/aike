defmodule AikeVision.Pdf do
  @moduledoc """
  Single-page PDF access through Poppler (`pdfinfo`, `pdftotext`, `pdftoppm`, `pdfimages`).

  Only single-page PDFs are read: reading only the first page of a bundle would silently
  drop the other pages. Digital documents embed the card as a small raster image, which
  OCR reads better at its native resolution than from the rendered page.

  ## Errors
    - `:unsupported_page_count`: the PDF has more than one page
    - the `AikeVision.Command` errors of the Poppler tools

  ## Examples

      :ok = AikeVision.Pdf.single_page(path)
      {:ok, text} = AikeVision.Pdf.text_layer(path, directory)
      {:ok, images} = AikeVision.Pdf.embedded_images(path, directory)
  """
  alias AikeVision.{Command, ImageHeader}

  @min_image_side 200
  @max_images 3

  @doc """
  Tells whether `bytes` start with the PDF signature.

  ## Parameters
    - bytes: the uploaded file

  ## Returns
    - `true` for a PDF, `false` otherwise
  """
  @spec pdf?(binary()) :: boolean()
  def pdf?(<<"%PDF-", _::binary>>), do: true
  def pdf?(_), do: false

  @doc """
  Checks that the PDF has exactly one page.

  ## Parameters
    - path: path of the PDF file

  ## Returns
    - `:ok`
    - `{:error, :unsupported_page_count}` or a command error
  """
  @spec single_page(Path.t()) :: :ok | {:error, :unsupported_page_count | Command.error()}
  def single_page(path) do
    with {:ok, info} <- Command.run("pdfinfo", [path]) do
      case Regex.run(~r/^Pages:\s+(\d+)\s*$/m, info) do
        [_, "1"] -> :ok
        _ -> {:error, :unsupported_page_count}
      end
    end
  end

  @doc """
  Reads the text layer of the first page, when the PDF has one.

  ## Parameters
    - path: path of the PDF file
    - directory: workspace for the output file

  ## Returns
    - `{:ok, text}` (empty for scanned PDFs)
    - `{:error, reason}` from `AikeVision.Command`
  """
  @spec text_layer(Path.t(), Path.t()) :: {:ok, String.t()} | {:error, Command.error()}
  def text_layer(path, directory) do
    output = Path.join(directory, "text-layer.txt")

    with {:ok, _} <- Command.run("pdftotext", ["-f", "1", "-l", "1", path, output]) do
      {:ok, File.read!(output)}
    end
  end

  @doc """
  Renders the first page as a PNG.

  ## Parameters
    - path: path of the PDF file
    - directory: workspace for the output file
    - size: longest side of the rendered page, in pixels

  ## Returns
    - `{:ok, png_path}`
    - `{:error, reason}` from `AikeVision.Command`
  """
  @spec render_page(Path.t(), Path.t(), pos_integer()) ::
          {:ok, Path.t()} | {:error, Command.error()}
  def render_page(path, directory, size) do
    prefix = Path.join(directory, "page")

    args =
      ~w(-f 1 -l 1 -singlefile -scale-to #{size} -png) ++ [path, prefix]

    with {:ok, _} <- Command.run("pdftoppm", args), do: {:ok, prefix <> ".png"}
  end

  @doc """
  Extracts the largest raster images of the first page.

  Bilevel masks (such as QR codes) and images with a side under 200 pixels (logos) are
  skipped. At most three images are returned, largest first.

  ## Parameters
    - path: path of the PDF file
    - directory: workspace for the extracted files

  ## Returns
    - `{:ok, png_paths}` (empty when the page has no usable image)
    - `{:error, reason}` from `AikeVision.Command`
  """
  @spec embedded_images(Path.t(), Path.t()) :: {:ok, [Path.t()]} | {:error, Command.error()}
  def embedded_images(path, directory) do
    prefix = Path.join(directory, "embedded")

    with {:ok, _} <- Command.run("pdfimages", ["-f", "1", "-l", "1", "-png", path, prefix]) do
      {:ok,
       (prefix <> "-*.png")
       |> Path.wildcard()
       |> Enum.flat_map(&candidate/1)
       |> Enum.sort_by(fn {area, _} -> area end, :desc)
       |> Enum.take(@max_images)
       |> Enum.map(fn {_, image} -> image end)}
    end
  end

  defp candidate(image) do
    with {:ok, bytes} <- File.read(image),
         {:ok, %{bilevel: false, width: width, height: height}} <- ImageHeader.read(bytes),
         true <- min(width, height) >= @min_image_side do
      [{width * height, image}]
    else
      _ -> []
    end
  end
end
