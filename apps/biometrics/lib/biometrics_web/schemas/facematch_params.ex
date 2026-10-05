defmodule BiometricsWeb.Schemas.FacematchParams do
  @moduledoc "Peri schemas for facematch request payloads."
  import Peri

  defschema(:create, %{
    "app_id" => :any,
    "external_id" => {:required, {:string, [min: 1, max: 256]}},
    "selfie_image" => {:required, :any},
    "document_image" => {:required, :any}
  })
end
