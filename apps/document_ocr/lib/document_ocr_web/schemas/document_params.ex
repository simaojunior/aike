defmodule DocumentOcrWeb.Schemas.DocumentParams do
  @moduledoc """
  Peri schemas for OCR JSON/base64 and multipart inputs, with the public camelCase field
  names (`appId`, `externalId`, `documentType`, `imageFront`, `imageBack`, `mimeType`,
  `pipelineVersion`).
  """
  import Peri
  @type_input {:enum, ["cnh", "drivers_license", "rg", "id_card"]}
  @country {:enum, ["BR", "BRA"]}
  @upload {:custom, {AikeHttp.Input, :upload}}
  @base %{
    "appId" => {:string, [min: 1, max: 256]},
    "externalId" => {:string, [min: 1, max: 256]}
  }
  @flat Map.merge(@base, %{"documentType" => @type_input, "country" => @country})
  @image %{
    "side" => {:required, {:enum, ["front", "back", "single"]}},
    "image" => {:required, {:custom, {AikeHttp.Input, :base64}}},
    "filename" => {:string, [min: 1, max: 256]},
    "mimeType" => {:string, [min: 1, max: 256]}
  }
  defschema(:json, Map.put(@flat, "images", {:required, {:custom, {__MODULE__, :images}}}))

  defschema(
    :nested_json,
    Map.merge(@base, %{
      "document" => {:required, %{"type" => @type_input, "country" => @country}},
      "images" => {:required, {:custom, {__MODULE__, :images}}}
    })
  )

  defschema(
    :front,
    Map.merge(@flat, %{"imageFront" => {:required, @upload}, "imageBack" => @upload})
  )

  defschema(
    :back,
    Map.merge(@flat, %{"imageFront" => @upload, "imageBack" => {:required, @upload}})
  )

  defschema(:file, Map.put(@flat, "file", {:required, @upload}))

  defschema(:resource, %{"id" => {:required, {:custom, {AikeHttp.Input, :uuid}}}})

  defschema(:reprocess, %{
    "id" => {:required, {:custom, {AikeHttp.Input, :uuid}}},
    "pipelineVersion" => {:required, {:string, [min: 1, max: 64]}}
  })

  def create(%{"document" => _} = params), do: nested_json(params)
  def create(%{"images" => _} = params), do: json(params)
  def create(%{"imageFront" => _} = params), do: front(params)
  def create(%{"imageBack" => _} = params), do: back(params)
  def create(params), do: file(params)

  def images(values) when is_list(values) and length(values) in 1..2 do
    with {:ok, images} <- validate_images(values) do
      sides = Enum.map(images, & &1["side"])
      if length(Enum.uniq(sides)) == length(sides), do: {:ok, images}, else: invalid_images()
    end
  end

  def images(_), do: invalid_images()

  defp validate_images(values) do
    results =
      Enum.with_index(values, fn value, index ->
        case Peri.validate({:required, @image}, value) do
          {:ok, image} ->
            {:ok, image}

          {:error, errors} ->
            {:error, Enum.map(List.wrap(errors), &prefix_path(&1, index))}
        end
      end)

    errors = for {:error, issues} <- results, issue <- issues, do: issue
    if errors == [], do: {:ok, for({:ok, image} <- results, do: image)}, else: {:error, errors}
  end

  defp prefix_path(error, index) do
    nested =
      if is_list(error.errors), do: Enum.map(error.errors, &prefix_path(&1, index)), else: nil

    %{error | path: [index | error.path || []], errors: nested}
  end

  defp invalid_images, do: {:error, "Invalid document images.", code: "invalid_images"}
end
