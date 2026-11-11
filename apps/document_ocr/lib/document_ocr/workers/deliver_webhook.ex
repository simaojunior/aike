defmodule DocumentOcr.Workers.DeliverWebhook do
  @moduledoc """
  Sends one webhook delivery and retries it with exponential backoff.

  A `2xx` answer marks the delivery `delivered`. Any other answer, a timeout or a refused
  target is retried; after the last attempt the delivery is `failed`. Redirects are not
  followed, and the target is checked before every attempt (`DocumentOcr.Webhooks.Target`).
  Deliveries of a deactivated endpoint stop. Logs carry the delivery ID and HTTP status
  only, never the URL or the body.

  ## Request
    - `POST` with a JSON body (camelCase keys)
    - `aike-event-id`: the delivery ID, to drop duplicates
    - `aike-event-type`: `extraction.completed`
    - `aike-signature`: `t=<unix time>,v1=<hex HMAC-SHA256>` (see
      `DocumentOcr.Webhooks.signature/3`)

  ## Configuration

      config :document_ocr, webhook_req_options: []

  `webhook_req_options` is merged into every request (tests use it to stub HTTP).
  """
  use Oban.Worker, queue: :webhooks, max_attempts: 12

  alias DocumentOcr.Repo
  alias DocumentOcr.Webhooks
  alias DocumentOcr.Webhooks.{Delivery, Target}
  alias KycCore.JsonKeyFormatter

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"delivery_id" => id}, attempt: attempt, max_attempts: max}) do
    case Repo.get(Delivery, id) |> Repo.preload(:endpoint) do
      %Delivery{status: "pending", endpoint: %{active: true}} = delivery ->
        attempt_delivery(delivery, attempt, max)

      _ ->
        {:cancel, :delivery_not_pending}
    end
  end

  defp attempt_delivery(delivery, attempt, max) do
    body = delivery.payload |> JsonKeyFormatter.format() |> Jason.encode!()

    result =
      with :ok <- Target.check(delivery.endpoint.url) do
        send_request(delivery, body)
      end

    record(result, delivery, attempt, max)
  end

  defp send_request(delivery, body) do
    timestamp = System.os_time(:second)
    secret = Webhooks.secret(delivery.endpoint_id)

    Req.post(
      [
        url: delivery.endpoint.url,
        body: body,
        headers: [
          {"content-type", "application/json"},
          {"aike-event-id", delivery.id},
          {"aike-event-type", delivery.event_type},
          {"aike-signature", Webhooks.signature(secret, timestamp, body)}
        ],
        redirect: false,
        retry: false,
        receive_timeout: 10_000,
        connect_options: [timeout: 5_000]
      ] ++ Application.get_env(:document_ocr, :webhook_req_options, [])
    )
  rescue
    _ -> {:error, :request_failed}
  end

  defp record({:ok, %Req.Response{status: status}}, delivery, attempt, _max)
       when status in 200..299 do
    update(delivery, %{
      status: "delivered",
      attempts: attempt,
      last_status_code: status,
      delivered_at: DateTime.utc_now()
    })
  end

  defp record(result, delivery, attempt, max) do
    status = status_code(result)
    final = attempt >= max

    update(delivery, %{
      status: final_status(final),
      attempts: attempt,
      last_status_code: status
    })

    Logger.warning("Webhook delivery failed",
      event: "webhook.delivery.failed",
      delivery_id: delivery.id,
      status: status,
      attempt: attempt
    )

    {:error, :webhook_delivery_failed}
  end

  defp status_code({:ok, %Req.Response{status: status}}), do: status
  defp status_code(_result), do: nil

  defp final_status(true), do: "failed"
  defp final_status(false), do: "pending"

  defp update(delivery, changes) do
    delivery |> Ecto.Changeset.change(changes) |> Repo.update!()
    :ok
  end
end
