defmodule DocumentClassifier.FadedDocumentTest do
  use ExUnit.Case, async: true
  alias DocumentClassifier.Engine.Tesseract

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

  test "a faded RG front photographed sideways is classified" do
    assert {:ok, %{"document" => %{"type" => "rg", "side" => "front"}}} =
             Tesseract.classify(faded_sideways_rg(), [])
  end

  defp faint_upright_rg do
    directory = Path.join(System.tmp_dir!(), "konoha-faint-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "rg.jpg")

    script = """
    import sys
    from PIL import Image, ImageDraw, ImageFont
    photo = Image.new('RGB', (1700, 1300), (40, 40, 44))
    card = Image.new('RGB', (1400, 950), (205, 228, 205))
    draw = ImageDraw.Draw(card)
    font = ImageFont.load_default(size=40)
    lines = ['REPUBLICA FEDERATIVA DO BRASIL', 'SECRETARIA DA SEGURANCA PUBLICA',
             'INSTITUTO DE IDENTIFICACAO', 'CARTEIRA DE IDENTIDADE', 'ASSINATURA DO TITULAR']
    for index, line in enumerate(lines):
        draw.text((60, 60 + index * 120), line, font=font, fill=(150, 190, 205))
    photo.paste(card, (150, 170))
    photo.save(sys.argv[1], quality=92)
    """

    {_, 0} = System.cmd("python3", ["-c", script, path])
    bytes = File.read!(path)
    File.rm_rf!(directory)
    bytes
  end

  test "ink too faint for grayscale and the blue channel is read with stretched contrast" do
    assert {:ok,
            %{
              "document" => %{"type" => "rg", "side" => "front"},
              "quality" => %{"acceptable" => true, "issues" => []}
            }} = Tesseract.classify(faint_upright_rg(), [])
  end

  test "quality uses the best read, not the noise of weaker preparations" do
    words = fn confidences -> Enum.map(confidences, &%{text: "KONOHA", confidence: &1}) end

    noisy_gray = words.([20, 35, 50, 54, 60])
    noisy_blue = words.([40, 55, 65, 70, 72])
    stretched = words.([78, 80, 86, 90, 91])

    assert Tesseract.quality_confidence([noisy_gray, noisy_blue, stretched]) == 86
    assert Tesseract.quality_confidence([noisy_gray]) == 50
    assert Tesseract.quality_confidence([]) == 0
  end
end
