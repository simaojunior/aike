defmodule DocumentOcrWeb.ServiceAccountAuth do
  def init(opts), do: opts

  def call(conn, opts) do
    AikeAuth.Plug.call(conn,
      app: :document_ocr,
      scopes: Keyword.get(opts, :scopes, [])
    )
  end
end
