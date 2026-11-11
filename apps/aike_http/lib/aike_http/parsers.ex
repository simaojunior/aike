defmodule AikeHttp.Parsers do
  @moduledoc "Syntax/size/media-type errors before Peri validation."
  import Plug.Conn
  def init(opts), do: Plug.Parsers.init(opts)

  def call(conn, opts) do
    Plug.Parsers.call(conn, opts)
  rescue
    Plug.Parsers.ParseError ->
      conn |> AikeHttp.Problem.send(400, "invalid_json") |> halt()

    Plug.Parsers.RequestTooLargeError ->
      conn |> AikeHttp.Problem.send(413, "payload_too_large") |> halt()

    Plug.Parsers.UnsupportedMediaTypeError ->
      conn |> AikeHttp.Problem.send(415, "unsupported_media_type") |> halt()
  end
end
