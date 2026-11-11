defmodule DocumentOcrWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :document_ocr
  plug(Plug.RequestId)
  plug(AikeHttp.Health)

  plug(AikeObservability.Plug,
    app: :document_ocr,
    repo: DocumentOcr.Repo,
    queues: ~w(preprocess ocr default maintenance)
  )

  plug(AikeHttp.ResponseHeaders)
  plug(DocumentOcrWeb.Auth)
  plug(DocumentOcrWeb.Observability)

  plug(AikeHttp.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    json_decoder: Jason,
    pass: [],
    length: 20_000_000
  )

  plug(DocumentOcrWeb.Router)
end
