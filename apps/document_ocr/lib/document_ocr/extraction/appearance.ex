defmodule DocumentOcr.Extraction.Appearance do
  @moduledoc """
  The side and subtype of an extracted document, from the images sent and the text read.

  The side follows the classifier rules (`AikeVision.DocumentMarkers`): a front and a back
  sent together, a digital CNH or an RG with markers of both sides show both sides
  (`single`). Otherwise the markers or the side of the only image sent decide. The subtype
  is `digital` when the text shows a digital signature and `printed` otherwise.

  ## Examples

      %{"side" => "single", "subtype" => "printed"} =
        DocumentOcr.Extraction.Appearance.describe("rg", ["front", "back"], text)
  """

  @doc """
  Describes the side and subtype of a document.

  ## Parameters
    - type: the document type (`"cnh"` or `"rg"`)
    - sides: the sides of the images sent
    - text: all the text read

  ## Returns
    - `%{"side" => side, "subtype" => subtype}`; side is `front`, `back`, `single` or
      `unknown`
  """
  @spec describe(String.t(), [String.t()], String.t()) :: %{String.t() => String.t()}
  def describe(type, sides, text) do
    markers = AikeVision.DocumentMarkers.analyze(text)
    %{"side" => side(type, Enum.sort(Enum.uniq(sides)), markers), "subtype" => subtype(markers)}
  end

  defp side(_type, ["back", "front"], _markers), do: "single"
  defp side(_type, ["single"], _markers), do: "single"
  defp side("cnh", _sides, %{digital: true}), do: "single"
  defp side("rg", _sides, %{rg_front: true, rg_back: true}), do: "single"
  defp side("rg", _sides, %{rg_front: true}), do: "front"
  defp side("rg", _sides, %{rg_back: true}), do: "back"
  defp side(_type, [side], _markers) when side in ["front", "back"], do: side
  defp side(_type, _sides, _markers), do: "unknown"

  defp subtype(%{digital: true}), do: "digital"
  defp subtype(_markers), do: "printed"
end
