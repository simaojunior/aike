defmodule DocumentClassifierWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :document_classifier
  plug(Plug.RequestId)
  plug(AikeHttp.Health)
  plug(AikeHttp.ResponseHeaders)
  plug(DocumentClassifierWeb.ShedLoad)
  plug(DocumentClassifierWeb.Auth)
  plug(DocumentClassifierWeb.ServiceAccountAuth)

  plug(AikeHttp.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    json_decoder: Jason,
    pass: [],
    length: 20_000_000
  )

  plug(DocumentClassifierWeb.Observability)
  plug(DocumentClassifierWeb.Router)
end
