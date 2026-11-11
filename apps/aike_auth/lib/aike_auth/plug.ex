defmodule AikeAuth.Plug do
  @moduledoc "Authenticates service credentials and authorizes any one of the required scopes."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    if Application.get_env(Keyword.fetch!(opts, :app), :service_account_auth_required, false) do
      authenticate(conn, Keyword.fetch!(opts, :scopes))
    else
      conn
    end
  end

  defp authenticate(conn, scopes) do
    with ["ApiKey " <> credentials] <- get_req_header(conn, "authorization"),
         [account, secret] <- String.split(credentials, ":", parts: 2),
         true <- byte_size(account) in 1..128 and byte_size(secret) in 1..512,
         {:ok, identity} <- AikeAuth.authenticate(account, secret) do
      if Enum.any?(scopes, &(&1 in identity.scopes)) do
        conn
        |> assign(:company_id, identity.company_id)
        |> assign(:service_account_id, identity.account_id)
        |> assign(:service_account, identity)
      else
        deny(conn, 403, "forbidden")
      end
    else
      {:error, :unavailable} -> deny(conn, 503, "service_unavailable")
      _ -> deny(conn, 401, "unauthorized")
    end
  end

  defp deny(conn, status, error) do
    conn = if status == 401, do: put_resp_header(conn, "www-authenticate", "ApiKey"), else: conn
    conn |> AikeHttp.Problem.send(status, error) |> halt()
  end
end
