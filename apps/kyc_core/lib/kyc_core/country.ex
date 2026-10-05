defmodule KycCore.Country do
  @type value :: :br
  @values [:br]
  @spec all() :: [value(), ...]
  def all, do: @values
  @spec valid?(term()) :: boolean()
  def valid?(value), do: value in @values
end
