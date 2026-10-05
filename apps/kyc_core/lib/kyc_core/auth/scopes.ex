defmodule KycCore.Auth.Scopes do
  @moduledoc "Allowed machine-to-machine scopes."

  @values [
    "ocr:write",
    "ocr:read",
    "classifier:write",
    "classifier:read",
    "facematch:write",
    "facematch:read",
    "biometrics:write",
    "biometrics:read"
  ]

  @spec all() :: [String.t()]
  def all, do: @values

  @spec valid?(term()) :: boolean()
  def valid?(scope), do: scope in @values
end
