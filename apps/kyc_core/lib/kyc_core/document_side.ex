defmodule KycCore.DocumentSide do
  @type value :: :front | :back | :single | :unknown
  @values [:front, :back, :single, :unknown]
  @spec all() :: [value(), ...]
  def all, do: @values
  @spec valid?(term()) :: boolean()
  def valid?(value), do: value in @values
end
