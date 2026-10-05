defmodule Biometrics.Engine.Fake do
  @behaviour Biometrics.Engine

  @impl true
  def compare(_selfie, _document, _opts) do
    {:ok,
     %{
       "match" => true,
       "similarity_score" => 0.98,
       "selfie_face_detected" => true,
       "document_face_detected" => true
     }}
  end
end
