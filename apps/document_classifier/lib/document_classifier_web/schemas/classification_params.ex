defmodule DocumentClassifierWeb.Schemas.ClassificationParams do
  @moduledoc "Peri validation of JSON/base64 and multipart classifier inputs."
  import Peri
  @upload {:custom, {AikeHttp.Input, :upload}}
  defschema(:json, %{"image" => {:required, {:custom, {AikeHttp.Input, :base64}}}})
  defschema(:file, %{"file" => {:required, @upload}})
  defschema(:image_upload, %{"image" => {:required, @upload}})

  def create(%{"file" => _} = params), do: file(params)
  def create(%{"image" => %Plug.Upload{}} = params), do: image_upload(params)
  def create(params), do: json(params)
end
