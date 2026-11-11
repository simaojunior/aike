defmodule BiometricsWeb.ServiceAccountAuth do
  def init(opts), do: opts

  def call(conn, opts) do
    AikeAuth.Plug.call(conn,
      app: :biometrics,
      scopes: Keyword.get(opts, :scopes, ["facematch:write", "biometrics:write"])
    )
  end
end
