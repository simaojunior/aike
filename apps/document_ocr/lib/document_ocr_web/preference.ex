defmodule DocumentOcrWeb.Preference do
  @moduledoc """
  Reads the `prefer` request header (RFC 7240) for extraction requests.

  `wait=N` asks the server to answer within N seconds with the finished extraction when
  possible. The wait is capped at `max_wait_seconds`. `respond-async` without `wait`, or
  no header, means no wait.

  ## Configuration

      config :document_ocr, max_wait_seconds: 10

  ## Examples

      conn = Plug.Conn.put_req_header(conn, "prefer", "wait=10")
      10 = DocumentOcrWeb.Preference.wait(conn)
  """

  @doc """
  Seconds the client is willing to wait, capped by the configuration.

  ## Parameters
    - conn: the request

  ## Returns
    - the seconds to wait, or `nil` when the client asked for no wait
  """
  @spec wait(Plug.Conn.t()) :: pos_integer() | nil
  def wait(conn),
    do: AikeHttp.Prefer.wait(conn, Application.get_env(:document_ocr, :max_wait_seconds, 10))
end
