defmodule DocumentClassifier.Engine.Fake do
  @moduledoc "Deterministic fixtures, not image recognition."
  @behaviour DocumentClassifier.Engine

  @impl true
  def classify(image, _opts) do
    result =
      case image do
        "fake:cnh_back" -> result("cnh", "back")
        "fake:rg_front" -> result("rg", "front")
        "fake:rg_back" -> result("rg", "back")
        "fake:rg_single" -> result("rg", "single")
        "fake:unknown" -> result("unknown", "unknown", 0.37, true, 0.91, [])
        "fake:bad_quality" -> result("cnh", "front", 0.98, false, 0.42, ["blur", "glare"])
        _ -> result("cnh", "front")
      end

    {:ok, result}
  end

  defp result(type, side, confidence \\ 0.99, acceptable \\ true, score \\ 0.96, issues \\ []) do
    %{
      "document" => %{"type" => type, "country" => "BR", "side" => side},
      "quality" => %{"acceptable" => acceptable, "score" => score, "issues" => issues},
      "confidence" => confidence
    }
  end
end
