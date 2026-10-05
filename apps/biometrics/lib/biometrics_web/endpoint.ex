defmodule BiometricsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :biometrics
  plug(Plug.RequestId)
  plug(BiometricsWeb.Auth)
  plug(Plug.Parsers, parsers: [:urlencoded, :multipart, :json], json_decoder: Jason, length: 20_000_000)
  plug(BiometricsWeb.Observability)
  plug(BiometricsWeb.Router)
end
