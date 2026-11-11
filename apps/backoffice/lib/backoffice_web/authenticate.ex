defmodule BackofficeWeb.Authenticate do
  @moduledoc "Resolves a human session independently of authorization."
  import Plug.Conn

  alias Backoffice.Sessions

  def init(opts), do: opts

  def call(conn, _) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, identity} <- Sessions.authenticate(token) do
      assign(conn, :identity, identity)
    else
      _ -> conn
    end
  end
end
