defmodule KycCore.DocumentType do
  @type value :: :cnh | :rg | :unknown
  @values [:cnh, :rg, :unknown]
  @spec all() :: [value(), ...]
  def all, do: @values
  @spec valid?(term()) :: boolean()
  def valid?(value), do: value in @values
end
