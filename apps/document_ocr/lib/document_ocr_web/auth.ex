defmodule DocumentOcrWeb.Auth do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _opts) when conn.request_path in ["/v1/companies", "/v1/service-accounts"],
    do: conn

  def call(conn, _opts) do
    if Application.get_env(:document_ocr, :service_account_auth_required, false) and
         match?(["ApiKey " <> _], get_req_header(conn, "authorization")) do
      conn
    else
      case Application.get_env(:document_ocr, :service_token) do
        nil ->
          if Application.get_env(:document_ocr, :auth_required, false), do: deny(conn), else: conn

        token when is_binary(token) and byte_size(token) > 0 ->
          case get_req_header(conn, "authorization") do
            ["Bearer " <> provided] ->
              if Plug.Crypto.secure_compare(provided, token), do: conn, else: deny(conn)

            _ ->
              deny(conn)
          end

        _ ->
          deny(conn)
      end
    end
  end

  defp deny(conn),
    do:
      conn
      |> put_resp_header("www-authenticate", "ApiKey")
      |> AikeHttp.Problem.send(401, "unauthorized")
      |> halt()
end
