defmodule DocumentClassifier.TestEngineFileErrors do
  @behaviour DocumentClassifier.Engine
  def classify("fake:" <> reason, _opts), do: {:error, String.to_existing_atom(reason)}
end

defmodule DocumentClassifier.FileErrorsTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn
  alias DocumentClassifier.Engine.Tesseract

  defp png(width, height) do
    <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 13::32, "IHDR", width::32, height::32, 8, 2, 0, 0, 0>>
  end

  defp two_page_pdf do
    directory = Path.join(System.tmp_dir!(), "konoha-pdf-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)

    script = """
    import sys
    from PIL import Image
    page = Image.new('RGB', (200, 200), 'white')
    page.save(sys.argv[1] + '/two.pdf', save_all=True, append_images=[page])
    """

    {_, 0} = System.cmd("python3", ["-c", script, directory])
    bytes = File.read!(Path.join(directory, "two.pdf"))
    File.rm_rf!(directory)
    bytes
  end

  describe "the Tesseract engine names why a file cannot be read" do
    test "an unsupported format" do
      assert Tesseract.classify("GIF89a" <> :binary.copy("x", 64), []) ==
               {:error, :unsupported_image}
    end

    test "an image above 20 megapixels" do
      assert Tesseract.classify(png(8064, 6048), []) == {:error, :image_too_large}
    end

    test "a PDF with more than one page" do
      assert Tesseract.classify(two_page_pdf(), []) == {:error, :unsupported_page_count}
    end

    test "a file above 10 MB" do
      assert Tesseract.classify(:binary.copy("x", 10_000_001), []) == {:error, :file_too_large}
    end
  end

  describe "each file problem has its own HTTP code" do
    setup do
      original = Application.get_env(:document_classifier, :engine)
      Application.put_env(:document_classifier, :engine, DocumentClassifier.TestEngineFileErrors)
      on_exit(fn -> Application.put_env(:document_classifier, :engine, original) end)
    end

    for {reason, status, code} <- [
          {"unsupported_image", 415, "unsupported_file"},
          {"image_too_large", 422, "image_too_large"},
          {"unsupported_page_count", 422, "unsupported_page_count"},
          {"file_too_large", 413, "file_too_large"}
        ] do
      @reason reason
      @status status
      @code code
      test "#{reason} answers #{status} #{code}" do
        response =
          conn(
            :post,
            "/v1/classifications",
            Jason.encode!(%{"image" => Base.encode64("fake:" <> @reason)})
          )
          |> put_req_header("content-type", "application/json")
          |> DocumentClassifierWeb.Endpoint.call([])

        assert response.status == @status
        body = Jason.decode!(response.resp_body)
        assert body["code"] == @code
        assert is_binary(body["detail"]) and body["detail"] != ""
      end
    end
  end
end
