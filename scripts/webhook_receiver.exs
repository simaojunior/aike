defmodule Aike.WebhookReceiver do
  @moduledoc """
  Local webhook receiver for manual tests. Prints each delivery, checks its signature and
  answers with `RESPOND_STATUS` (default 204; use 500 to watch the retries).

      WEBHOOK_SECRET=whsec_... mix run --no-start scripts/webhook_receiver.exs
  """
  @behaviour Plug
  import Plug.Conn

  @tolerance_seconds 300

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    {:ok, body, conn} = read_body(conn)
    headers = Map.new(conn.req_headers)

    IO.puts("""

    #{DateTime.utc_now() |> DateTime.truncate(:second)} #{conn.method} #{conn.request_path}
      aike-event-id:   #{headers["aike-event-id"]}
      aike-event-type: #{headers["aike-event-type"]}
      signature:       #{verify(headers["aike-signature"], body)}
      body:            #{pretty(body)}
      answer:          #{status()}
    """)

    send_resp(conn, status(), "")
  end

  defp verify(nil, _body), do: "MISSING"

  defp verify(header, body) do
    with [_, timestamp, signature] <- Regex.run(~r/\At=(\d+),v1=([0-9a-f]{64})\z/, header),
         secret when is_binary(secret) <- System.get_env("WEBHOOK_SECRET") do
      expected =
        :crypto.mac(:hmac, :sha256, secret, timestamp <> "." <> body)
        |> Base.encode16(case: :lower)

      age = System.os_time(:second) - String.to_integer(timestamp)

      cond do
        not Plug.Crypto.secure_compare(expected, signature) -> "INVALID"
        abs(age) > @tolerance_seconds -> "TOO OLD (#{age}s)"
        true -> "valid (#{age}s old)"
      end
    else
      nil -> "not checked: set WEBHOOK_SECRET"
      _ -> "MALFORMED"
    end
  end

  defp pretty(body) do
    case Jason.decode(body) do
      {:ok, json} ->
        Jason.encode!(json, pretty: true) |> String.replace("\n", "\n                   ")

      _ ->
        inspect(body)
    end
  end

  defp status, do: String.to_integer(System.get_env("RESPOND_STATUS", "204"))
end

port = String.to_integer(System.get_env("PORT", "4100"))
{:ok, _} = Application.ensure_all_started(:bandit)
{:ok, _} = Bandit.start_link(plug: Aike.WebhookReceiver, ip: {127, 0, 0, 1}, port: port)

IO.puts(
  "Webhook receiver on http://127.0.0.1:#{port}/hooks (answer #{System.get_env("RESPOND_STATUS", "204")})"
)

Process.sleep(:infinity)
