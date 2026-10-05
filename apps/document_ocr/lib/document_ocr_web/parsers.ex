defmodule DocumentOcrWeb.Parsers do
  @moduledoc "Parses request bodies and normalizes malformed JSON errors."

  import Plug.Conn

  @spec init(keyword()) :: Plug.Parsers.parser()
  def init(opts), do: Plug.Parsers.init(opts)

  @spec call(Plug.Conn.t(), Plug.Parsers.parser()) :: Plug.Conn.t()
  def call(conn, opts) do
    Plug.Parsers.call(conn, opts)
  rescue
    _error in Plug.Parsers.ParseError ->
      request_id = List.first(get_req_header(conn, "x-request-id")) || Ecto.UUID.generate()

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("x-request-id", request_id)
      |> send_resp(
        400,
        Jason.encode!(%{
          error: %{
            code: "invalid_json",
            message: "Request body must be valid JSON.",
            requestId: request_id
          }
        })
      )
      |> halt()
  end
end
