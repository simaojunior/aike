defmodule BiometricsWeb.ServiceAccountAuth do
  @moduledoc """
  Service account scope check of the biometrics API.

  It calls `AikeAuth.Plug` with the scopes of the route. The default scopes are
  `facematch:write` and `biometrics:write`.
  """
  def init(opts), do: opts

  def call(conn, opts) do
    AikeAuth.Plug.call(conn,
      app: :biometrics,
      scopes: Keyword.get(opts, :scopes, ["facematch:write", "biometrics:write"])
    )
  end
end
