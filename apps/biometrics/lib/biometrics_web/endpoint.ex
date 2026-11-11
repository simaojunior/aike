defmodule BiometricsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :biometrics
  plug(Plug.RequestId)
  plug(AikeHttp.Health)
  plug(AikeObservability.Plug, app: :biometrics, repo: Biometrics.Repo, queues: ~w(biometrics))
  plug(AikeHttp.ResponseHeaders)
  plug(BiometricsWeb.Auth)

  plug(AikeHttp.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    json_decoder: Jason,
    length: 20_000_000
  )

  plug(BiometricsWeb.Observability)
  plug(BiometricsWeb.Router)
end
