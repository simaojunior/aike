defmodule DocumentClassifier.Storage.Fake do
  @moduledoc "Reserved fake/* keys select synthetic bytes for local API exercises."
  @behaviour DocumentClassifier.Storage

  @fixtures %{
    "fake/cnh-front.jpg" => "fake:cnh_front",
    "fake/cnh-back.jpg" => "fake:cnh_back",
    "fake/rg-front.jpg" => "fake:rg_front",
    "fake/rg-back.jpg" => "fake:rg_back",
    "fake/rg-single.jpg" => "fake:rg_single",
    "fake/unknown.jpg" => "fake:unknown",
    "fake/bad-quality.jpg" => "fake:bad_quality"
  }

  @impl true
  def get(key), do: {:ok, Map.get(@fixtures, key, "fake:cnh_front")}
end
