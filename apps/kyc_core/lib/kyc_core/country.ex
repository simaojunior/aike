defmodule KycCore.Country do
  @moduledoc """
  Supported document countries. Requests and storage use ISO 3166-1 alpha-2 (`"BR"`);
  API responses use alpha-3 (`"BRA"`), the same in every service.

  ## Examples

      "BRA" = KycCore.Country.alpha3("BR")
  """
  @type value :: :br
  @values [:br]

  @spec all() :: [value(), ...]
  def all, do: @values

  @spec valid?(term()) :: boolean()
  def valid?(value), do: value in @values

  @doc """
  The ISO 3166-1 alpha-3 code of a country in API responses.

  ## Parameters
    - country: an alpha-2 code

  ## Returns
    - `"BRA"` for Brazil; other values unchanged
  """
  @spec alpha3(String.t()) :: String.t()
  def alpha3("BR"), do: "BRA"
  def alpha3(country), do: country
end
