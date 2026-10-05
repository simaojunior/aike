defmodule DocumentClassifier.Result do
  @moduledoc "Checks the engine boundary without imposing capture or onboarding policy."
  @types Enum.map(KycCore.DocumentType.all(), &Atom.to_string/1)
  @sides Enum.map(KycCore.DocumentSide.all(), &Atom.to_string/1)
  @countries Enum.map(KycCore.Country.all(), &(Atom.to_string(&1) |> String.upcase()))

  def validate(%{
        "document" => %{"type" => type, "country" => country, "side" => side} = document,
        "quality" =>
          %{"acceptable" => acceptable, "score" => score, "issues" => issues} = quality,
        "confidence" => confidence
      }) do
    if type in @types and country in @countries and side in @sides and
         is_boolean(acceptable) and probability?(score) and probability?(confidence) and
         is_list(issues) and Enum.all?(issues, &is_binary/1) do
      {:ok,
       %{
         "document" => Map.take(document, ["type", "country", "side"]),
         "quality" => Map.take(quality, ["acceptable", "score", "issues"]),
         "confidence" => confidence
       }}
    else
      {:error, :invalid_engine_result}
    end
  end

  def validate(_), do: {:error, :invalid_engine_result}
  defp probability?(value), do: is_number(value) and value >= 0 and value <= 1
end
