defmodule DocumentClassifierWeb.ServiceAccountAuth do
  def init(opts), do: opts

  def call(conn, opts) do
    AikeAuth.Plug.call(conn,
      app: :document_classifier,
      scopes: Keyword.get(opts, :scopes, ["classifier:write"])
    )
  end
end
