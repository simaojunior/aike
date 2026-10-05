defmodule DocumentClassifier.ClassificationResponse do
  @moduledoc "Builds the versioned array response for uploaded classification files."

  def from_upload(result, upload, started_at) do
    data =
      case result["document"]["type"] do
        "cnh" -> [entry(result, upload)]
        "rg" -> [entry(result, upload)]
        _ -> []
      end

    %{
      "id" => Ecto.UUID.generate(),
      "version" => "v1",
      "data" => data,
      "metadata" => %{
        "files_info" => [file_info(upload)],
        "processing_time_ms" => elapsed_ms(started_at)
      }
    }
  end

  defp entry(result, upload) do
    %{
      "classification" => %{
        "type" => type(result["document"]["type"]),
        "country" => country(result["document"]["country"]),
        "side" => side(result["document"]["side"]),
        "confidence" => result["confidence"]
      },
      "quality" => %{
        "is_accepted" => result["quality"]["acceptable"],
        "issues" => result["quality"]["issues"]
      },
      "file_info" => %{"fieldname" => upload_field(upload)}
    }
  end

  defp file_info(upload) do
    {:ok, bytes} = File.read(upload.path)

    %{
      "fieldname" => upload_field(upload),
      "name" => upload.filename,
      "size" => byte_size(bytes),
      "mimetype" => upload.content_type,
      "sha256" => :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    }
  end

  defp upload_field(%Plug.Upload{path: _}), do: "file"
  defp type("cnh"), do: "drivers_license"
  defp type("rg"), do: "id_card"
  defp type(value), do: value
  defp country("BR"), do: "BRA"
  defp country(value), do: value
  defp side("front"), do: "only_front"
  defp side("back"), do: "only_back"
  defp side("single"), do: "front_and_back"
  defp side(value), do: value
  defp elapsed_ms(started_at), do: System.monotonic_time(:millisecond) - started_at
end
