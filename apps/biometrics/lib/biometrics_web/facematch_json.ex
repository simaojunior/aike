defmodule BiometricsWeb.FacematchJSON do
  @moduledoc "JSON representations for facematch resources."

  @spec data(%{id: term(), status: term(), result: term()}) :: map()
  def data(%{result: nil} = session), do: %{id: session.id, status: session.status, result: nil}

  def data(%{result: result} = session) do
    result.data
    |> Map.put("id", session.id)
    |> Map.put("status", session.status)
    |> Map.put("decision", session.decision)
    |> Map.put("result", result.data)
  end
end
