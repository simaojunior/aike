defmodule DocumentClassifierWeb.Schemas.ClassificationParams do
  @moduledoc "Peri schemas for classifier request payloads."
  import Peri

  defschema(:create, %{
    "file" => :any,
    "image" => :any,
    "source" => :any
  })
end
