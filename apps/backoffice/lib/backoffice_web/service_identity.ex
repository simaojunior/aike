defmodule BackofficeWeb.ServiceIdentity do
  @moduledoc "Private introspection endpoint, isolated from human sessions and authenticated before parsing."
  import Plug.Conn
  @path "/internal/v1/service-accounts/introspect"

  alias BackofficeWeb.Schemas.Params

  def init(opts), do: opts

  def call(%{request_path: @path} = conn, _) do
    token = Application.get_env(:backoffice, :introspection_token)

    with "POST" <- conn.method,
         true <- is_binary(token) and byte_size(token) > 0,
         ["Bearer " <> provided] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(provided, token) do
      handle(conn)
    else
      _ -> respond(conn, 401, %{error: "unauthorized"})
    end
  end

  def call(conn, _), do: conn

  defp handle(conn) do
    case read_body(conn, length: 4_096, read_length: 4_096, read_timeout: 3_000) do
      {:ok, body, conn} ->
        introspect(conn, body)

      {:more, _, conn} ->
        respond(conn, 413, %{error: "payload_too_large"})

      {:error, _} ->
        respond(conn, 400, %{error: "invalid_request"})
    end
  end

  defp introspect(conn, body) do
    with {:ok, params} <- Jason.decode(body),
         {:ok, %{"accountId" => account, "secret" => secret}} <- Params.introspect(params) do
      authenticate(conn, account, secret)
    else
      {:error, %Jason.DecodeError{}} -> respond(conn, 400, %{error: "invalid_json"})
      {:error, errors} -> conn |> AikeHttp.Problem.validation(errors) |> halt()
    end
  end

  defp authenticate(conn, account, secret) do
    case Backoffice.ServiceIdentity.authenticate(account, secret) do
      {:ok, identity} -> respond(conn, 200, identity)
      {:error, :unauthorized} -> respond(conn, 401, %{error: "unauthorized"})
      _ -> respond(conn, 503, %{error: "service_unavailable"})
    end
  end

  defp respond(conn, status, %{error: code}) do
    conn = if status == 401, do: put_resp_header(conn, "www-authenticate", "Bearer"), else: conn
    conn |> AikeHttp.Problem.send(status, code) |> halt()
  end

  defp respond(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(KycCore.JsonKeyFormatter.format(body)))
    |> halt()
  end
end
