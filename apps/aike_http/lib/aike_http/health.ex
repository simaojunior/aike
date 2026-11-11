defmodule AikeHttp.Health do
  @moduledoc """
  Liveness check: `GET /health` answers `200 {"status":"ok"}` before authentication.

  It tells an orchestrator or load balancer that the process accepts HTTP requests. It does
  not check the database or storage, so a slow dependency never restarts a healthy node.
  It sits right after `Plug.RequestId` in every endpoint and halts the connection.

  ## Examples

      plug(Plug.RequestId)
      plug(AikeHttp.Health)
  """
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method, path_info: ["health"]} = conn, _opts)
      when method in ["GET", "HEAD"] do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(200, ~s({"status":"ok"}))
    |> halt()
  end

  def call(conn, _opts), do: conn
end
