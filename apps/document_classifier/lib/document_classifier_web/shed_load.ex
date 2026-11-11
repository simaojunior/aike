defmodule DocumentClassifierWeb.ShedLoad do
  @moduledoc """
  Refuses a request before its body is read when this node's waiting line is full.

  Under a traffic peak this keeps uploads out of memory and spares the authentication
  call, so the node stays responsive and the client can retry later or on another node.
  Only `POST` requests are checked. Emits `[:document_classifier, :load_shed]`.

  ## Configuration

      plug DocumentClassifierWeb.ShedLoad

  The default limiter is `AikeVision.Documents`; `limiter: name` uses another one.
  `retry_after_seconds` in `config :aike_vision` sets the `retry-after` header.
  """
  import Plug.Conn

  def init(opts), do: Keyword.get(opts, :limiter, AikeVision.Documents)

  def call(%Plug.Conn{method: "POST"} = conn, limiter),
    do: shed(conn, AikeVision.Limiter.saturated?(limiter))

  def call(conn, _limiter), do: conn

  defp shed(conn, false), do: conn

  defp shed(conn, true) do
    :telemetry.execute([:document_classifier, :load_shed], %{count: 1}, %{})

    conn
    |> put_resp_header("retry-after", retry_after())
    |> AikeHttp.Problem.send(503, "service_unavailable")
    |> halt()
  end

  @doc """
  Seconds a refused client should wait before it retries.

  ## Returns
    - the `retry-after` header value, such as `"2"`
  """
  @spec retry_after() :: String.t()
  def retry_after, do: "#{Application.get_env(:aike_vision, :retry_after_seconds, 2)}"
end
