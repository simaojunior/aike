defmodule BiometricsWeb.Schemas.FacematchParams do
  @moduledoc """
  Peri validates facematch fields and upload types before ingestion, with the public
  camelCase names (`appId`, `externalId`, `selfieImage`, `documentImage`).
  """
  import Peri

  defschema(:resource, %{
    "id" => {:required, {:custom, {AikeHttp.Input, :uuid}}},
    "appId" => {:string, [min: 1, max: 256]}
  })

  defschema(:create, %{
    "appId" => {:string, [min: 1, max: 256]},
    "externalId" => {:string, [min: 1, max: 256]},
    "selfieImage" => {:required, {:custom, {AikeHttp.Input, :upload}}},
    "documentImage" => {:required, {:custom, {AikeHttp.Input, :upload}}}
  })
end
