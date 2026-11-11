defmodule DocumentClassifier.Engine.TextRules do
  @moduledoc """
  Classification and quality from recognized text.

  Type rules live in `AikeVision.DocumentMarkers`. Scores are heuristics, not calibrated
  probabilities: a known type scores 0.75.

  - Side: a digital CNH is `single`; an RG is `front`, `back` or `single` from the markers
    found; otherwise `unknown`
  - Quality is acceptable only without issues: `low_text_confidence` (median word
    confidence under 70, or under 20 characters) and the image issues given by the engine
    (`low_resolution`, `document_not_detected`)

  ## Examples

      %{"document" => %{"type" => "cnh"}, "quality" => %{"acceptable" => true}} =
        DocumentClassifier.Engine.TextRules.classify(
          "REPUBLICA FEDERATIVA DO BRASIL CARTEIRA NACIONAL DE HABILITACAO",
          90
        )
  """
  alias AikeVision.DocumentMarkers

  @doc """
  Classifies recognized text.

  ## Parameters
    - text: all the text read from the document
    - confidence: median word confidence of the best OCR pass, from 0 to 100
    - image_issues: issues found on the image, such as `"low_resolution"` (default `[]`)

  ## Returns
    - `%{"document" => %{"type", "country", "side"}, "confidence", "quality" =>
      %{"acceptable", "score", "issues"}}`
  """
  @spec classify(String.t(), number(), [String.t()]) :: map()
  def classify(text, confidence, image_issues \\ []) do
    markers = DocumentMarkers.analyze(text)
    type = Atom.to_string(markers.type)
    readable = String.length(String.trim(text)) >= 20 and confidence >= 70
    issues = image_issues ++ text_issues(readable)

    %{
      "document" => %{"type" => type, "country" => "BR", "side" => side(type, markers)},
      "confidence" => score(type),
      "quality" => %{
        "acceptable" => issues == [],
        "score" => max(0, min(confidence / 100, 1)),
        "issues" => issues
      }
    }
  end

  defp side("cnh", %{digital: true}), do: "single"
  defp side("rg", %{rg_front: true, rg_back: true}), do: "single"
  defp side("rg", %{rg_front: true}), do: "front"
  defp side("rg", %{rg_back: true}), do: "back"
  defp side(_, _), do: "unknown"
  defp score("unknown"), do: 0.0
  defp score(_), do: 0.75
  defp text_issues(true), do: []
  defp text_issues(false), do: ["low_text_confidence"]
end
