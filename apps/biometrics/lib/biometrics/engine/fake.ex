defmodule Biometrics.Engine.Fake do
  @moduledoc """
  Test engine with a fixed match, in the result format of `Biometrics.Engine.OpenCV`.
  It never reads the images.
  """
  @behaviour Biometrics.Engine

  @impl true
  def compare(_selfie, _document, _opts) do
    {:ok,
     %{
       "match" => true,
       "similarity_score" => 0.98,
       "selfie_face_detected" => true,
       "document_face_detected" => true,
       "resources" => [resource("selfie_image"), resource("document_image")],
       "faces" => %{"selfie_image" => 1, "document_image" => 1},
       "issues" => %{"selfie_image" => [], "document_image" => []}
     }}
  end

  defp resource(fieldname) do
    %{
      "fieldname" => fieldname,
      "page" => 0,
      "face" => %{
        "confidence" => 0.95,
        "bounding_box" => %{"top" => 0.2, "left" => 0.3, "width" => 0.3, "height" => 0.4}
      }
    }
  end
end
