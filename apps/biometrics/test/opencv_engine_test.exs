defmodule Biometrics.OpenCVEngineTest do
  use ExUnit.Case, async: true
  alias Biometrics.Engine.OpenCV

  @moduletag :face_models

  defp synthetic(directory, name) do
    script = """
    import sys
    from PIL import Image, ImageDraw, ImageFont
    card = Image.new('RGB', (964, 708), (214, 245, 200))
    draw = ImageDraw.Draw(card)
    draw.text((40, 60), 'NOME', font=ImageFont.load_default(size=16), fill='black')
    draw.text((40, 90), 'NARUTO UZUMAKI', font=ImageFont.load_default(size=24), fill='black')
    card.save(sys.argv[1] + '/' + sys.argv[2])
    """

    {_, 0} = System.cmd("python3", ["-c", script, directory, name])
    File.read!(Path.join(directory, name))
  end

  setup do
    directory = Path.join(System.tmp_dir!(), "aike-face-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "images without a face are compared to nothing and report where the face is missing",
       %{directory: directory} do
    selfie = synthetic(directory, "selfie.png")
    document = synthetic(directory, "document.pdf")

    assert {:ok, result} = OpenCV.compare(selfie, document, [])

    assert %{
             "match" => false,
             "similarity_score" => nil,
             "selfie_face_detected" => false,
             "document_face_detected" => false,
             "resources" => [],
             "faces" => %{"selfie_image" => 0, "document_image" => 0},
             "issues" => %{"selfie_image" => ["no_face"], "document_image" => ["no_face"]}
           } = result
  end

  test "bytes that are not an image or a PDF are refused" do
    assert OpenCV.compare("not an image", "not a document", []) == {:error, :invalid_image}
  end
end
