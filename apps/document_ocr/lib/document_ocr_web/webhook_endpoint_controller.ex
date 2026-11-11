defmodule DocumentOcrWeb.WebhookEndpointController do
  @moduledoc """
  Manages the webhook endpoints of the authenticated company.

  The company comes from the service account; `app_id` is used only when authentication
  is disabled. An endpoint of another company is reported as not found.

  ## Examples

      POST   /v1/webhook-endpoints      {"url": "https://konoha.example/hooks"}  -> 201
      GET    /v1/webhook-endpoints                                               -> 200
      DELETE /v1/webhook-endpoints/:id                                           -> 204
  """
  use DocumentOcrWeb, :controller
  action_fallback(DocumentOcrWeb.FallbackController)

  alias DocumentOcr.Webhooks
  alias DocumentOcrWeb.Schemas.WebhookEndpointParams
  alias DocumentOcrWeb.{ValidateParams, WebhookEndpointJSON}
  alias KycCore.JsonKeyFormatter

  plug(ValidateParams,
    create: &WebhookEndpointParams.create/1,
    index: &WebhookEndpointParams.index/1,
    delete: &WebhookEndpointParams.delete/1
  )

  @doc """
  Registers an endpoint and returns its signing secret once.

  ## Parameters
    - conn: the request
    - params: `url`

  ## Returns
    - `201` with `id`, `url`, `secret` and `createdAt`; `422` for an invalid URL
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, %{"url" => url} = params) do
    with company when is_binary(company) <- company(conn, params),
         {:ok, endpoint, secret} <- Webhooks.create_endpoint(company, url) do
      conn
      |> put_status(201)
      |> json(JsonKeyFormatter.format(WebhookEndpointJSON.created(endpoint, secret)))
    else
      nil -> {:error, :invalid_request}
      error -> error
    end
  end

  @doc """
  Lists the active endpoints of the company.

  ## Parameters
    - conn: the request
    - params: no parameters

  ## Returns
    - `200` with `data`
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    case company(conn, params) do
      nil ->
        {:error, :invalid_request}

      company ->
        json(
          conn,
          JsonKeyFormatter.format(WebhookEndpointJSON.index(Webhooks.list_endpoints(company)))
        )
    end
  end

  @doc """
  Deactivates an endpoint of the company.

  ## Parameters
    - conn: the request
    - params: `id`

  ## Returns
    - `204`; `404` when the endpoint does not exist or belongs to another company
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, %{"id" => id} = params) do
    with company when is_binary(company) <- company(conn, params),
         {:ok, _endpoint} <- Webhooks.delete_endpoint(company, id) do
      send_resp(conn, 204, "")
    else
      nil -> {:error, :invalid_request}
      error -> error
    end
  end

  defp company(conn, params), do: conn.assigns[:company_id] || params["app_id"]
end
