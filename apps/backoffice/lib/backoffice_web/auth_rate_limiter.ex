defmodule BackofficeWeb.AuthRateLimiter do
  @moduledoc "Limits authentication requests by the socket peer, without trusting forwarded headers."
  import Plug.Conn

  def init(opts), do: opts

  def call(%{method: "POST", request_path: "/v1/auth/" <> _} = conn, _) do
    result = Backoffice.RateLimits.check("ip:" <> to_string(:inet.ntoa(conn.remote_ip)), 60)
    respond(result, conn)
  end

  def call(conn, _), do: conn
  defp respond(:ok, conn), do: conn
  defp respond(error, conn), do: conn |> BackofficeWeb.FallbackController.call(error) |> halt()
end
