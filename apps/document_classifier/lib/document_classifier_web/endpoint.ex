defmodule DocumentClassifierWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :document_classifier
  plug(Plug.RequestId)
  plug(DocumentClassifierWeb.Auth)
  plug(DocumentClassifierWeb.ServiceAccountAuth)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    json_decoder: Jason,
    pass: [],
    length: 20_000_000
  )

  plug(DocumentClassifierWeb.Observability)
  plug(DocumentClassifierWeb.Router)
end
