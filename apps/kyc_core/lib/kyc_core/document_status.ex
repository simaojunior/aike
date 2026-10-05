defmodule KycCore.DocumentStatus do
  @type value :: String.t()
  @values ["pending", "processing", "completed", "requires_confirmation", "failed", "rejected"]
  @spec all() :: [String.t()]
  def all, do: @values
  @spec valid?(term()) :: boolean()
  def valid?(value), do: value in @values
end
