defmodule DocumentOcrWeb.Schemas.WebhookEndpointParams do
  @moduledoc """
  Peri schemas for the webhook endpoint API.

  ## Examples

      {:ok, %{"url" => _}} =
        DocumentOcrWeb.Schemas.WebhookEndpointParams.create(%{"url" => "https://konoha.example/hooks"})
  """
  import Peri

  defschema(:create, %{
    "appId" => {:string, [min: 1, max: 256]},
    "url" => {:required, {:string, [min: 1, max: 2048]}}
  })

  defschema(:index, %{"appId" => {:string, [min: 1, max: 256]}})

  defschema(:delete, %{
    "appId" => {:string, [min: 1, max: 256]},
    "id" => {:required, {:custom, {AikeHttp.Input, :uuid}}}
  })
end
