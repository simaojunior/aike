defmodule BackofficeWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :backoffice
  plug(Plug.RequestId)
  plug(AikeHttp.Health)
  plug(AikeHttp.ResponseHeaders)
  plug(BackofficeWeb.Observability)
  plug(BackofficeWeb.ServiceIdentity)
  plug(BackofficeWeb.Authenticate)
  plug(BackofficeWeb.EnsureAuthenticated)
  plug(BackofficeWeb.AuthRateLimiter)
  plug(AikeHttp.Parsers, parsers: [:json], json_decoder: Jason, pass: [], length: 1_000_000)
  plug(BackofficeWeb.Router)
end
