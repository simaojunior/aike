defmodule DocumentOcr.TesseractOCRTest do
  use ExUnit.Case, async: true
  alias DocumentOcr.Extraction.CNHLabels
  alias DocumentOcr.OCR.{Tesseract, TesseractPython}

  @opts [engine_version: Tesseract.version()]

  test "extracts CNH fields from a synthetic card as PNG and PDF without personal data" do
    directory =
      Path.join(System.tmp_dir!(), "aike-ocr-fixture-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    script = """
    import sys
    from PIL import Image, ImageDraw, ImageFont
    card = Image.new('RGB', (964, 708), (214, 245, 200))
    draw = ImageDraw.Draw(card)
    label = ImageFont.load_default(size=16)
    value = ImageFont.load_default(size=24)
    brown = (110, 60, 30)
    for x, y, name, text in [
        (40, 60, 'NOME', 'NARUTO UZUMAKI'),
        (40, 200, 'CPF', '529.982.247-25'),
        (520, 200, 'DATA NASCIMENTO', '12/03/1990'),
    ]:
        draw.text((x, y), name, font=label, fill='black')
        draw.rectangle((x - 6, y + 26, x + 400, y + 66), outline='black')
        draw.text((x + 4, y + 32), text, font=value, fill=brown)
    card.save(sys.argv[1] + '/card.png')
    card.save(sys.argv[1] + '/card.pdf')
    card.save(sys.argv[1] + '/bundle.pdf', save_all=True, append_images=[card])
    """

    assert {_, 0} = System.cmd("python3", ["-c", script, directory])

    python = [engine_version: TesseractPython.version()]

    assert {:ok, reference} =
             TesseractPython.extract(
               File.read!(Path.join(directory, "card.png")),
               python
             )

    assert {:ok, %{"fields" => %{"cpf" => %{"value" => "52998224725"}}}} =
             CNHLabels.extract(reference)

    for file <- ["card.png", "card.pdf"] do
      assert {:ok, raw} = Tesseract.extract(File.read!(Path.join(directory, file)), @opts)
      assert {:ok, %{"fields" => person}} = CNHLabels.extract(raw)
      assert person["full_name"]["value"] == "NARUTO UZUMAKI"
      assert person["cpf"]["value"] == "52998224725"
      assert person["birth_date"]["value"] == "1990-03-12"
    end

    assert {:error, :invalid_image} =
             Tesseract.extract(File.read!(Path.join(directory, "bundle.pdf")), @opts)
  end

  test "reads light red CNH values and the isolated category" do
    directory =
      Path.join(System.tmp_dir!(), "aike-ocr-red-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    script = """
    import sys
    from PIL import Image, ImageDraw, ImageFont
    card = Image.new('RGB', (964, 708), (217, 250, 196))
    draw = ImageDraw.Draw(card)
    label = ImageFont.load_default(size=16)
    value = ImageFont.load_default(size=24)
    red = (215, 160, 125)
    draw.text((40, 40), 'NOME', font=label, fill='black')
    draw.text((44, 72), 'NARUTO UZUMAKI', font=value, fill='black')
    draw.text((40, 160), 'CPF', font=label, fill='black')
    draw.text((44, 192), '529.982.247-25', font=value, fill='black')
    draw.text((520, 160), 'DATA NASCIMENTO', font=label, fill='black')
    draw.text((524, 192), '12/03/1990', font=value, fill='black')
    draw.text((720, 300), 'CAT. HAB.', font=label, fill='black')
    draw.text((724, 320), 'AB', font=value, fill=red)
    for x, name, text in [(40, 'N REGISTRO', '52998224725'), (380, 'VALIDADE', '26/07/2031')]:
        draw.text((x, 420), name, font=label, fill='black')
        draw.text((x + 4, 440), text, font=value, fill=red)
    card.save(sys.argv[1] + '/card.png')
    """

    assert {_, 0} = System.cmd("python3", ["-c", script, directory])

    assert {:ok, raw} =
             Tesseract.extract(
               File.read!(Path.join(directory, "card.png")),
               @opts ++ [document_type: "cnh"]
             )

    assert Enum.all?(raw["text"], &Regex.match?(~r/\A0\.(\d+|r\d+)\z/, &1["source"]))
    assert {:ok, %{"fields" => fields}} = CNHLabels.extract(raw)
    assert fields["category"]["value"] == "AB"
    assert fields["expiration_date"]["value"] == "2031-07-26"
    assert fields["registration_number"]["value"] == "52998224725"
  end

  test "refuses another engine version and invalid input" do
    assert {:error, :unsupported_engine_version} =
             Tesseract.extract("bytes", engine_version: "tesseract-0")

    assert {:error, :invalid_image} = Tesseract.extract("not an image", @opts)
    assert {:error, :invalid_image} = Tesseract.extract("", @opts)
    assert {:error, :invalid_image} = Tesseract.extract(:binary.copy("x", 10_000_001), @opts)
  end
end
