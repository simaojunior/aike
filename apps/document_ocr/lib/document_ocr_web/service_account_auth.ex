defmodule DocumentOcrWeb.ServiceAccountAuth do
  @moduledoc """
  Service account scope check of the OCR API.

  It calls `AikeAuth.Plug` with the scopes of the route.
  """
  def init(opts), do: opts

  def call(conn, opts) do
    AikeAuth.Plug.call(conn,
      app: :document_ocr,
      scopes: Keyword.get(opts, :scopes, [])
    )
  end
end
