defmodule AikeVisionTest do
  use ExUnit.Case, async: true
  alias AikeVision.{Document, Image, ImageHeader, Tesseract, Workspace}

  defp png(width, height, color_type, depth \\ 8) do
    <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 13::32, "IHDR", width::32, height::32, depth,
      color_type, 0, 0, 0>>
  end

  defp jpeg(width, height, components) do
    app0 = <<0xFF, 0xE0, 16::16, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0>>
    <<0xFF, 0xD8, app0::binary, 0xFF, 0xC0, 17::16, 8, height::16, width::16, components>>
  end

  test "reads dimensions and color from headers without decoding pixels" do
    assert {:ok, %{format: :png, width: 640, height: 480, colored: true, bilevel: false}} =
             ImageHeader.read(png(640, 480, 2))

    assert {:ok, %{colored: false, bilevel: true}} = ImageHeader.read(png(600, 600, 0, 1))

    assert {:ok, %{format: :jpeg, width: 1200, height: 1600, colored: true}} =
             ImageHeader.read(jpeg(1200, 1600, 3))

    assert {:ok, %{colored: false}} = ImageHeader.read(jpeg(800, 600, 1))
  end

  test "rejects other formats, animations, empty and oversized images" do
    assert {:error, :unsupported_image} = ImageHeader.read("GIF89a")
    assert {:error, :unsupported_image} = ImageHeader.read(png(10, 10, 2) <> "acTL")
    assert {:error, :unsupported_image} = ImageHeader.read(png(0, 10, 2))
    assert {:error, :image_too_large} = ImageHeader.read(png(8064, 6048, 2))
    assert {:error, :image_too_large} = ImageHeader.read(jpeg(40_000, 40_000, 3))
  end

  test "parses Tesseract TSV and drops empty or unrecognized words" do
    tsv = """
    level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
    4\t1\t1\t1\t1\t0\t10\t20\t300\t30\t-1\t
    5\t1\t1\t1\t1\t1\t10\t20\t100\t30\t91.5\tNOME
    5\t1\t1\t1\t1\t2\t120\t20\t90\t30\t-1\tX
    5\t1\t1\t1\t1\t3\t220\t20\t90\t30\t40\t\s
    """

    assert [%{text: "NOME", confidence: 91.5, box: {10, 20, 110, 50}, line: {1, 1, 1}}] =
             Tesseract.parse(tsv)
  end

  test "removes the workspace on success, on error and when the deadline kills the work" do
    parent = self()

    assert {:ok, :done} =
             Workspace.run(
               fn directory ->
                 send(parent, {:directory, directory})
                 {:ok, :done}
               end,
               1_000
             )

    assert_received {:directory, first}
    refute File.exists?(first)

    assert {:error, :runtime_exception} =
             Workspace.run(
               fn directory ->
                 send(parent, {:directory, directory})
                 raise "boom"
               end,
               1_000
             )

    assert_received {:directory, second}
    refute File.exists?(second)

    assert {:error, :timeout} =
             Workspace.run(
               fn directory ->
                 send(parent, {:directory, directory})
                 Process.sleep(:infinity)
               end,
               50
             )

    assert_received {:directory, third}
    refute File.exists?(third)
  end

  test "finds a sideways document and crops it from the table around it" do
    script = """
    import sys
    from PIL import Image, ImageDraw, ImageFont
    photo = Image.new('RGB', (1800, 1400), (140, 95, 60))
    card = Image.new('RGB', (900, 560), (205, 230, 210))
    draw = ImageDraw.Draw(card)
    font = ImageFont.load_default(size=34)
    for y, text in enumerate(['REPUBLICA FEDERATIVA DO BRASIL', 'SECRETARIA DA SEGURANCA PUBLICA',
                              'INSTITUTO DE IDENTIFICACAO', 'REGISTRO GERAL 1234567',
                              'NATURALIDADE PORTO ALEGRE', 'CARTEIRA DE IDENTIDADE']):
        draw.text((40, 40 + y * 80), text, font=font, fill=(20, 40, 20))
    photo.paste(card, (450, 420))
    photo.rotate(90, expand=True).save(sys.argv[1], quality=90)
    """

    assert {:ok, {size, region}} =
             Workspace.run(
               fn directory ->
                 path = Path.join(directory, "photo.jpg")
                 {_, 0} = System.cmd("python3", ["-c", script, path])
                 {:ok, image, _} = Image.decode(File.read!(path))
                 {:ok, upright, legible} = Document.orient(image, directory)
                 {:ok, {Image.size(upright), Document.region(upright, legible)}}
               end,
               30_000
             )

    assert size == {1800, 1400}
    {left, top, right, bottom} = region
    assert left > 350 and left < 450 and right > 1350 and right < 1450
    assert top > 330 and top < 420 and bottom > 980 and bottom < 1080
  end

  test "stretch turns the paper white and light ink black" do
    paper = List.duplicate(236, 90)
    light_ink = List.duplicate(160, 10)

    gray =
      (paper ++ light_ink)
      |> Nx.tensor(type: :u8)
      |> Nx.reshape({10, 10})
      |> Evision.Mat.from_nx()

    stretched =
      gray |> Image.stretch() |> Evision.Mat.to_nx(Nx.BinaryBackend) |> Nx.to_flat_list()

    assert Enum.take(stretched, 90) |> Enum.uniq() == [255]
    assert Enum.drop(stretched, 90) |> Enum.uniq() == [0]
  end

  test "a JPEG above 20 megapixels is read at the smallest reduction that fits" do
    assert {:ok, %{scale: 1}} = ImageHeader.read(jpeg(4000, 3000, 3))
    assert {:ok, %{scale: 2}} = ImageHeader.read(jpeg(8064, 6048, 3))
    assert {:ok, %{scale: 4}} = ImageHeader.read(jpeg(16_000, 12_000, 3))
    assert {:ok, %{scale: 8}} = ImageHeader.read(jpeg(30_000, 30_000, 3))
    assert {:ok, %{scale: 1}} = ImageHeader.read(png(640, 480, 2))
  end

  test "a 48 megapixel phone photo decodes at half size without loading it whole" do
    directory = Path.join(System.tmp_dir!(), "konoha-48mp-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    script = """
    import sys
    from PIL import Image
    Image.new('RGB', (8064, 6048), (214, 245, 200)).save(sys.argv[1] + '/photo.jpg', quality=80)
    """

    {_, 0} = System.cmd("python3", ["-c", script, directory])

    assert {:ok, image, %{width: 8064, height: 6048, scale: 2}} =
             Image.decode(File.read!(Path.join(directory, "photo.jpg")))

    assert Image.size(image) == {4032, 3024}
  end

  defp faded_sideways_rg do
    directory = Path.join(System.tmp_dir!(), "konoha-faded-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "rg.jpg")

    script = """
    import sys, random
    from PIL import Image, ImageDraw, ImageFont
    random.seed(7)
    photo = Image.new('RGB', (1600, 2100))
    pixels = photo.load()
    for y in range(2100):
        for x in range(1600):
            value = 25 + random.randint(0, 45)
            pixels[x, y] = (value, value, value + 4)
    card = Image.new('RGB', (1500, 1000), (205, 228, 205))
    draw = ImageDraw.Draw(card)
    font = ImageFont.load_default(size=34)
    lines = ['REPUBLICA FEDERATIVA DO BRASIL', 'ESTADO DE KONOHA', 'SECRETARIA DA SEGURANCA PUBLICA',
             'INSTITUTO DE IDENTIFICACAO', 'CARTEIRA DE IDENTIDADE', 'ASSINATURA DO TITULAR', 'POLEGAR DIREITO']
    for index, line in enumerate(lines):
        draw.text((60, 60 + index * 120), line, font=font, fill=(120, 165, 125))
    photo.paste(card.rotate(90, expand=True), (300, 300))
    photo.save(sys.argv[1], quality=90)
    """

    {_, 0} = System.cmd("python3", ["-c", script, path])
    bytes = File.read!(path)
    File.rm_rf!(directory)
    bytes
  end

  test "a faded card photographed sideways on a dark textured table is turned upright" do
    {:ok, image, _} = Image.decode(faded_sideways_rg())

    {:ok, {upright, legible}} =
      Workspace.run(
        fn directory ->
          with {:ok, upright, legible} <- Document.orient(image, directory),
               do: {:ok, {upright, legible}}
        end,
        60_000
      )

    assert Image.size(upright) == {2100, 1600}
    assert length(legible) >= 8
    assert Document.region(upright, legible) != nil
  end

  defp card_with_photo_boxes do
    directory = Path.join(System.tmp_dir!(), "konoha-boxes-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "card.jpg")

    script = """
    import sys
    from PIL import Image, ImageDraw, ImageFont
    photo = Image.new('RGB', (1600, 1400), (40, 40, 44))
    card = Image.new('RGB', (1200, 900), (205, 228, 205))
    draw = ImageDraw.Draw(card)
    font = ImageFont.load_default(size=34)
    for index, line in enumerate(['REPUBLICA FEDERATIVA DO BRASIL', 'SECRETARIA DA SEGURANCA PUBLICA']):
        draw.text((60, 40 + index * 60), line, font=font, fill=(40, 70, 45))
    draw.rectangle((80, 200, 560, 860), fill=(250, 250, 250))
    draw.rectangle((640, 200, 1120, 860), fill=(245, 245, 240))
    photo.paste(card, (200, 250))
    photo.save(sys.argv[1], quality=92)
    """

    {_, 0} = System.cmd("python3", ["-c", script, path])
    bytes = File.read!(path)
    File.rm_rf!(directory)
    bytes
  end

  test "the region keeps the whole card when white photo boxes fill most of it" do
    {:ok, image, _} = Image.decode(card_with_photo_boxes())

    {:ok, {upright, legible}} =
      Workspace.run(
        fn directory ->
          with {:ok, upright, legible} <- Document.orient(image, directory),
               do: {:ok, {upright, legible}}
        end,
        60_000
      )

    {left, top, right, bottom} = Document.region(upright, legible)
    assert left <= 220 and right >= 1380
    assert top <= 270 and bottom >= 1130
  end
end
