defmodule DocumentOcrWeb.Schemas.DocumentParams do
  @moduledoc "Peri schemas for document API payloads."
  import Peri

  defschema(:create, %{
    "app_id" => :any,
    "external_id" => :any,
    "document_type" => :any,
    "country" => :any,
    "image_front" => :any,
    "image_back" => :any,
    "images" => :any,
    "document" => :any
  })

  defschema(:reprocess, %{
    "pipeline_version" => {:required, {:string, [min: 1, max: 64]}}
  })
end
