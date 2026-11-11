defmodule DocumentOcr.Webhooks.Delivery do
  @moduledoc """
  One event to send to one endpoint: the outbox row of a webhook.

  It is written in the same transaction as the document state change, so no event is lost
  and none is sent for a change that rolled back. Its ID is the event ID that receivers
  use to drop duplicates.

  ## Fields
    - `id`: event ID (UUID), sent as `Aike-Event-Id`
    - `endpoint_id`, `document_id`, `run_id`: the receiver, the extraction and its run;
      the database allows one event of each type per endpoint and run
    - `event_type`: `extraction.completed`
    - `payload`: the JSON body; IDs and status only, no personal data
    - `status`: `pending`, `delivered` or `failed` (all attempts used)
    - `attempts`, `last_status_code`, `delivered_at`: delivery history
  """
  use DocumentOcr, :model

  @type t :: %__MODULE__{}

  schema "webhook_deliveries" do
    field(:run_id, :binary_id)
    field(:event_type, :string)
    field(:payload, :map)
    field(:status, :string, default: "pending")
    field(:attempts, :integer, default: 0)
    field(:last_status_code, :integer)
    field(:delivered_at, :utc_datetime_usec)
    belongs_to(:endpoint, DocumentOcr.Webhooks.Endpoint)
    belongs_to(:document, DocumentOcr.Documents.Document)
    timestamps()
  end
end
