defmodule DocumentOcrWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :document_ocr
  plug(Plug.RequestId)
  plug(DocumentOcrWeb.Auth)
  plug(DocumentOcrWeb.Observability)

  plug(DocumentOcrWeb.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    json_decoder: Jason,
    pass: [],
    length: 20_000_000
  )

  plug(DocumentOcrWeb.Router)
end
