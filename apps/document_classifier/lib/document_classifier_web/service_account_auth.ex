defmodule DocumentClassifierWeb.ServiceAccountAuth do
  import Plug.Conn
  alias KycCore.Auth.{Secret, ServiceAccount}

  def init(opts), do: opts

  def call(conn, opts) do
    if Application.get_env(:document_classifier, :service_account_auth_required, false),
      do: authenticate(conn, Keyword.get(opts, :scopes, ["classifier:write"])),
      else: conn
  end

  defp authenticate(conn, scopes) do
    with ["ApiKey " <> credentials] <- get_req_header(conn, "authorization"),
         [account_id, secret] <- String.split(credentials, ":", parts: 2),
         true <- account_id != "" and secret != "",
         %ServiceAccount{active: true} = account <- lookup(account_id),
         true <- Secret.valid?(secret, account.secret_hash) do
      if Enum.any?(scopes, &(&1 in account.scopes)) do
        assign(conn, :company_id, account.company_id)
        |> assign(:service_account_id, account.account_id)
        |> assign(:service_account, account)
      else
        deny(conn, 403, "forbidden")
      end
    else
      _ -> deny(conn, 401, "unauthorized")
    end
  end

  defp lookup(account_id),
    do:
      Application.fetch_env!(:document_classifier, :service_account_repo).get_by(ServiceAccount,
        account_id: account_id
      )

  defp deny(conn, status, error),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(%{error: error}))
      |> halt()
end
