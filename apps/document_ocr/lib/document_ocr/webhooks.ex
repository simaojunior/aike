defmodule DocumentOcr.Webhooks do
  @moduledoc """
  Webhook endpoints of each company and the events sent to them.

  When an extraction reaches a final status (`completed`, `requires_confirmation`,
  `rejected` or `failed`), one delivery per active endpoint of the company is written in
  the same transaction and sent by `DocumentOcr.Workers.DeliverWebhook`. The payload holds
  IDs and the status only, never personal data: the receiver reads the result with
  `GET /v1/extractions/:id`, where authorization is checked again.

  Each endpoint signs with its own secret, derived from the server key and the endpoint ID
  (`HMAC-SHA256(webhook_signing_key, endpoint_id)`), so no secret is stored. The secret is
  shown once, when the endpoint is created.

  ## Configuration

      config :document_ocr,
        webhook_signing_key: "at least 32 random bytes",
        webhook_require_https: true

  In production the key comes from `WEBHOOK_SIGNING_KEY`.

  ## Examples

      {:ok, endpoint, secret} = DocumentOcr.Webhooks.create_endpoint("konoha", "https://konoha.example/hooks")
      [^endpoint] = DocumentOcr.Webhooks.list_endpoints("konoha")
      {:ok, _} = DocumentOcr.Webhooks.delete_endpoint("konoha", endpoint.id)
  """
  use DocumentOcr, :repository

  alias DocumentOcr.Documents.Document
  alias DocumentOcr.Webhooks.{Delivery, Endpoint}
  alias DocumentOcr.Workers.DeliverWebhook

  @event_type "extraction.completed"
  @final_statuses ~w(completed requires_confirmation rejected failed)

  @doc """
  Registers a webhook endpoint for a company.

  ## Parameters
    - company_id: the company of the authenticated service account
    - url: the URL that receives events

  ## Returns
    - `{:ok, endpoint, secret}`: the secret is not stored and is returned only here
    - `{:error, changeset}` when the URL is not accepted

  ## Example

      {:ok, endpoint, "whsec_" <> _} =
        DocumentOcr.Webhooks.create_endpoint("konoha", "https://konoha.example/hooks")
  """
  @spec create_endpoint(String.t(), String.t()) ::
          {:ok, Endpoint.t(), String.t()} | {:error, Ecto.Changeset.t()}
  def create_endpoint(company_id, url) do
    with {:ok, endpoint} <-
           %Endpoint{}
           |> Endpoint.changeset(%{company_id: company_id, url: url})
           |> Repo.insert() do
      {:ok, endpoint, secret(endpoint.id)}
    end
  end

  @doc """
  Lists the active endpoints of a company, oldest first.

  ## Parameters
    - company_id: the company of the authenticated service account

  ## Returns
    - the endpoints
  """
  @spec list_endpoints(String.t()) :: [Endpoint.t()]
  def list_endpoints(company_id) do
    Endpoint
    |> where(company_id: ^company_id, active: true)
    |> order_by(:inserted_at)
    |> Repo.all()
  end

  @doc """
  Deactivates an endpoint of a company. Its pending deliveries stop.

  ## Parameters
    - company_id: the company of the authenticated service account
    - id: the endpoint ID

  ## Returns
    - `{:ok, endpoint}`
    - `{:error, :not_found}` when the endpoint does not exist or belongs to another company
  """
  @spec delete_endpoint(String.t(), String.t()) :: {:ok, Endpoint.t()} | {:error, :not_found}
  def delete_endpoint(company_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Endpoint{} = endpoint <-
           Repo.get_by(Endpoint, id: id, company_id: company_id, active: true) do
      endpoint |> Ecto.Changeset.change(active: false) |> Repo.update()
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  The signing secret of an endpoint.

  ## Parameters
    - endpoint_id: the endpoint ID

  ## Returns
    - the secret, such as `"whsec_..."`
  """
  @spec secret(Ecto.UUID.t()) :: String.t()
  def secret(endpoint_id) do
    key = Application.fetch_env!(:document_ocr, :webhook_signing_key)
    "whsec_" <> Base.url_encode64(:crypto.mac(:hmac, :sha256, key, endpoint_id), padding: false)
  end

  @doc """
  The `Aike-Signature` header value for a body.

  The receiver recomputes `HMAC-SHA256(secret, "<timestamp>.<body>")`, compares it in
  constant time with `v1` and refuses old timestamps to stop replays.

  ## Parameters
    - secret: the endpoint secret
    - timestamp: Unix time in seconds
    - body: the exact request body

  ## Returns
    - `"t=<timestamp>,v1=<hex signature>"`

  ## Example

      "t=1760000000,v1=" <> _ = DocumentOcr.Webhooks.signature(secret, 1_760_000_000, body)
  """
  @spec signature(String.t(), integer(), String.t()) :: String.t()
  def signature(secret, timestamp, body) do
    digest = :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{body}")
    "t=#{timestamp},v1=#{Base.encode16(digest, case: :lower)}"
  end

  @doc """
  Writes the deliveries of a document that reached a final status.

  Call it inside the transaction that changes the status. Statuses that are not final
  write nothing.

  ## Parameters
    - document: the document after the change

  ## Returns
    - `:ok`
  """
  @spec record(Document.t()) :: :ok
  def record(%Document{status: status} = document) when status in @final_statuses do
    payload = payload(document)

    for endpoint <- list_endpoints(document.app_id) do
      id = Ecto.UUID.generate()

      delivery =
        Repo.insert!(%Delivery{
          id: id,
          endpoint_id: endpoint.id,
          document_id: document.id,
          run_id: document.run_id,
          event_type: @event_type,
          payload: Map.put(payload, "id", id)
        })

      Oban.insert!(DeliverWebhook.new(%{"delivery_id" => delivery.id}))
    end

    :ok
  end

  def record(_document), do: :ok

  defp payload(document) do
    %{
      "type" => @event_type,
      "version" => "v1",
      "occurred_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "data" => %{"id" => document.id, "run_id" => document.run_id, "status" => document.status}
    }
  end
end
