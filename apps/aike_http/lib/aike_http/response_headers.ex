defmodule AikeHttp.ResponseHeaders do
  @moduledoc "Ensures Phoenix-rendered failures also use the problem media type."
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    register_before_send(conn, fn conn ->
      if conn.status && conn.status >= 400 do
        conn
        |> put_resp_content_type("application/problem+json")
        |> put_resp_header("cache-control", "no-store")
      else
        conn
      end
    end)
  end
end
