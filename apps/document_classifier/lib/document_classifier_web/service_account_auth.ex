defmodule DocumentClassifierWeb.ServiceAccountAuth do
  @moduledoc """
  Service account scope check of the classifier API.

  It calls `AikeAuth.Plug` with the scopes of the route. The default scope is
  `classifier:write`.
  """
  def init(opts), do: opts

  def call(conn, opts) do
    AikeAuth.Plug.call(conn,
      app: :document_classifier,
      scopes: Keyword.get(opts, :scopes, ["classifier:write"])
    )
  end
end
