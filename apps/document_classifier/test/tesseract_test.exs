defmodule DocumentClassifier.TesseractTest do
  use ExUnit.Case, async: true
  alias DocumentClassifier.Engine.{Tesseract, TesseractPython}

  test "runs real OCR on synthetic PNG and PDF without personal data" do
    directory = Path.join(System.tmp_dir!(), "aike-fixture-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    script = """
    import sys
    from PIL import Image, ImageDraw, ImageFont
    image = Image.new('RGB', (1600, 400), 'white')
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=42)
    draw.text((40, 50), 'REPUBLICA FEDERATIVA DO BRASIL', font=font, fill='black')
    draw.text((40, 160), 'CARTEIRA NACIONAL DE HABILITACAO', font=font, fill='black')
    image.save(sys.argv[1] + '/document.png')
    image.save(sys.argv[1] + '/document.pdf')
    image.save(sys.argv[1] + '/bundle.pdf', save_all=True, append_images=[image])
    """

    assert {_, 0} = System.cmd("python3", ["-c", script, directory])

    for extension <- ["png", "pdf"] do
      assert {:ok, result} =
               Tesseract.classify(File.read!(Path.join(directory, "document.#{extension}")), [])

      assert result["document"]["type"] == "cnh"
      assert {:ok, _} = DocumentClassifier.Result.validate(result)
    end

    assert {:error, :unsupported_page_count} =
             Tesseract.classify(File.read!(Path.join(directory, "bundle.pdf")), [])
  end

  test "reads a small embedded card in a digital PDF and ignores the portal header" do
    directory = Path.join(System.tmp_dir!(), "aike-fixture-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    script = """
    import io, sys
    from PIL import Image, ImageDraw, ImageFont
    card = Image.new('RGB', (482, 354), (214, 245, 200))
    draw = ImageDraw.Draw(card)
    font = ImageFont.load_default(size=22)
    draw.text((10, 20), 'REPUBLICA FEDERATIVA DO BRASIL', font=font, fill='black')
    draw.text((10, 60), 'CARTEIRA NACIONAL DE HABILITACAO', font=font, fill='black')
    jpeg = io.BytesIO()
    card.save(jpeg, 'JPEG', quality=90)
    jpeg = jpeg.getvalue()

    def pdf(name, with_card):
        content = b'BT /F1 14 Tf 40 800 Td (REPUBLICA FEDERATIVA DO BRASIL) Tj 0 -16 Td (SECRETARIA NACIONAL DE TRANSITO - SENATRAN) Tj 0 -16 Td (Documento assinado com certificado digital) Tj ET'
        resources = b'/Font << /F1 5 0 R >>'
        extra = []
        if with_card:
            content += b' q 60 0 0 44 30 560 cm /Card Do Q'
            resources += b' /XObject << /Card 6 0 R >>'
            extra = [b'<< /Type /XObject /Subtype /Image /Width 482 /Height 354 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length %d >>\\nstream\\n' % len(jpeg) + jpeg + b'\\nendstream']
        objects = [
            b'<< /Type /Catalog /Pages 2 0 R >>',
            b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << ' + resources + b' >> /Contents 4 0 R >>',
            b'<< /Length %d >>\\nstream\\n' % len(content) + content + b'\\nendstream',
            b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
            *extra,
        ]
        out = bytearray(b'%PDF-1.4\\n')
        offsets = []
        for number, body in enumerate(objects, 1):
            offsets.append(len(out))
            out += b'%d 0 obj\\n' % number + body + b'\\nendobj\\n'
        xref = len(out)
        out += b'xref\\n0 %d\\n0000000000 65535 f \\n' % (len(objects) + 1)
        out += b''.join(b'%010d 00000 n \\n' % offset for offset in offsets)
        out += b'trailer\\n<< /Size %d /Root 1 0 R >>\\nstartxref\\n%d\\n%%%%EOF\\n' % (len(objects) + 1, xref)
        open(sys.argv[1] + '/' + name, 'wb').write(out)

    pdf('card.pdf', True)
    pdf('header_only.pdf', False)
    """

    assert {_, 0} = System.cmd("python3", ["-c", script, directory])

    assert {:ok, %{"document" => %{"type" => "cnh", "side" => "single"}}} =
             Tesseract.classify(File.read!(Path.join(directory, "card.pdf")), [])

    assert {:ok, %{"document" => %{"type" => "unknown", "side" => "unknown"}}} =
             Tesseract.classify(File.read!(Path.join(directory, "header_only.pdf")), [])
  end

  test "reads an RG photographed sideways" do
    directory = Path.join(System.tmp_dir!(), "aike-fixture-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    script = """
    import sys
    from PIL import Image, ImageDraw, ImageFont
    image = Image.new('RGB', (1600, 900), (205, 230, 205))
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=40)
    for y, text in enumerate(['SECRETARIA DA SEGURANCA PUBLICA', 'INSTITUTO DE IDENTIFICACAO',
                              'REGISTRO GERAL 1234567', 'NATURALIDADE PORTO ALEGRE RS',
                              'DOC ORIGEM C NASC 1234', 'LEI N 7.116 DE 29/08/83']):
        draw.text((60, 60 + y * 130), text, font=font, fill=(20, 40, 20))
    image.rotate(90, expand=True).save(sys.argv[1] + '/rg.jpg', quality=85)
    """

    assert {_, 0} = System.cmd("python3", ["-c", script, directory])

    assert {:ok, %{"document" => %{"type" => "rg", "side" => "single"}}} =
             Tesseract.classify(File.read!(Path.join(directory, "rg.jpg")), [])
  end

  test "measures quality on the document region, not on the whole photo" do
    directory = Path.join(System.tmp_dir!(), "aike-fixture-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    script = """
    import random, sys
    from PIL import Image, ImageDraw, ImageFont
    random.seed(7)

    def table(size):
        image = Image.new('RGB', size, (140, 95, 60))
        draw = ImageDraw.Draw(image)
        for _ in range(400):
            x, y = random.randrange(size[0]), random.randrange(size[1])
            draw.line((x, y, x + random.randrange(40, 200), y + random.randrange(-6, 6)),
                      fill=(random.randrange(90, 170), random.randrange(60, 120), 40), width=2)
        return image

    def card(scale):
        image = Image.new('RGB', (round(900 * scale), round(560 * scale)), (205, 230, 210))
        draw = ImageDraw.Draw(image)
        font = ImageFont.load_default(size=round(34 * scale))
        for y, text in enumerate(['REPUBLICA FEDERATIVA DO BRASIL', 'SECRETARIA DA SEGURANCA PUBLICA',
                                  'INSTITUTO DE IDENTIFICACAO', 'REGISTRO GERAL 1234567',
                                  'NATURALIDADE PORTO ALEGRE', 'CARTEIRA DE IDENTIDADE']):
            draw.text((round(40 * scale), round((40 + y * 80) * scale)), text, font=font, fill=(20, 40, 20))
        return image

    photo = table((1800, 1400))
    photo.paste(card(1), (450, 420))
    photo.save(sys.argv[1] + '/on_table.jpg', quality=90)

    tiny = table((1000, 800))
    tiny.paste(card(0.45), (300, 250))
    tiny.save(sys.argv[1] + '/tiny.jpg', quality=90)

    table((1800, 1400)).save(sys.argv[1] + '/no_document.jpg', quality=90)
    """

    assert {_, 0} = System.cmd("python3", ["-c", script, directory])
    classify = &Tesseract.classify(File.read!(Path.join(directory, &1)), [])

    assert {:ok, %{"document" => %{"type" => "rg"}, "quality" => on_table}} =
             classify.("on_table.jpg")

    assert on_table["acceptable"]
    assert on_table["issues"] == []

    assert {:ok, %{"quality" => tiny}} = classify.("tiny.jpg")
    refute tiny["acceptable"]
    assert tiny["issues"] == ["low_resolution"]

    assert {:ok, %{"document" => %{"type" => "unknown"}, "quality" => empty}} =
             classify.("no_document.jpg")

    assert "document_not_detected" in empty["issues"]
  end

  test "the Python reference engine still classifies" do
    directory = Path.join(System.tmp_dir!(), "aike-fixture-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    script = """
    import sys
    from PIL import Image, ImageDraw, ImageFont
    image = Image.new('RGB', (1600, 400), 'white')
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=42)
    draw.text((40, 50), 'REPUBLICA FEDERATIVA DO BRASIL', font=font, fill='black')
    draw.text((40, 160), 'CARTEIRA NACIONAL DE HABILITACAO', font=font, fill='black')
    image.save(sys.argv[1] + '/document.png')
    """

    assert {_, 0} = System.cmd("python3", ["-c", script, directory])

    assert {:ok, %{"document" => %{"type" => "cnh"}}} =
             TesseractPython.classify(
               File.read!(Path.join(directory, "document.png")),
               []
             )
  end

  test "rejects malformed content and oversized input" do
    assert {:error, :unsupported_image} = Tesseract.classify("not an image", [])
    assert {:error, :file_too_large} = Tesseract.classify(:binary.copy("x", 10_000_001), [])
  end
end
