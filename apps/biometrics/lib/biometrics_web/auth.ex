defmodule BiometricsWeb.Auth do
  @moduledoc """
  Static bearer token authentication for the biometrics API.

  A request with an `ApiKey` header passes when service account authentication is required.
  Other requests need the configured service token.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if service_account_request?(conn), do: conn, else: legacy_call(conn)
  end

  defp service_account_request?(conn) do
    Application.get_env(:biometrics, :service_account_auth_required, false) and
      match?(["ApiKey " <> _], get_req_header(conn, "authorization"))
  end

  defp legacy_call(conn), do: legacy_call(conn, Application.get_env(:biometrics, :service_token))

  defp legacy_call(conn, nil) do
    if Application.get_env(:biometrics, :auth_required, false), do: deny(conn), else: conn
  end

  defp legacy_call(conn, token) when is_binary(token) and byte_size(token) > 0,
    do: authorize(get_req_header(conn, "authorization"), conn, token)

  defp legacy_call(conn, _token), do: deny(conn)

  defp authorize(["Bearer " <> provided], conn, token) do
    if Plug.Crypto.secure_compare(provided, token), do: conn, else: deny(conn)
  end

  defp authorize(_header, conn, _token), do: deny(conn)

  defp deny(conn),
    do:
      conn
      |> put_resp_header("www-authenticate", "ApiKey")
      |> AikeHttp.Problem.send(401, "unauthorized")
      |> halt()
end
