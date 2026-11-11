defmodule AikeObservability.Plug do
  @moduledoc "Dedicated scrape authentication, independent of customer service accounts."
  import Plug.Conn

  def init(opts), do: opts

  def call(%{request_path: "/metrics"} = conn, opts) do
    token = Application.get_env(Keyword.fetch!(opts, :app), :metrics_token)

    cond do
      not is_binary(token) or byte_size(token) == 0 ->
        respond(conn, 404, "not_found\n")

      not authenticated?(conn, token) ->
        respond(conn, 401, "unauthorized\n")

      conn.method != "GET" ->
        conn |> put_resp_header("allow", "GET") |> respond(405, "method_not_allowed\n")

      true ->
        case AikeObservability.Queues.render(opts[:repo], opts[:app], opts[:queues]) do
          {:ok, body} -> respond(conn, 200, body)
          {:error, _} -> respond(conn, 503, "metrics_unavailable\n")
        end
    end
  end

  def call(conn, _opts), do: conn

  defp authenticated?(conn, expected) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> supplied] -> Plug.Crypto.secure_compare(supplied, expected)
      _ -> false
    end
  end

  defp respond(conn, status, body) do
    conn
    |> put_resp_header("content-type", "text/plain; version=0.0.4; charset=utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, body)
    |> halt()
  end
end
