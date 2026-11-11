defmodule BiometricsWeb.ValidateParams do
  @moduledoc """
  Parameter validation plug of the biometrics API.

  It delegates to `AikeHttp.ValidateParams`.
  """
  defdelegate init(opts), to: AikeHttp.ValidateParams
  defdelegate call(conn, opts), to: AikeHttp.ValidateParams
end
