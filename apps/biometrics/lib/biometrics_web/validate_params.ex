defmodule BiometricsWeb.ValidateParams do
  defdelegate init(opts), to: AikeHttp.ValidateParams
  defdelegate call(conn, opts), to: AikeHttp.ValidateParams
end
