defmodule KycCore.DocumentType do
  @moduledoc """
  Document types: `:cnh` (driver's license), `:rg` (identity card) and `:unknown`.

  Internal values are short Brazilian names; API responses use the public names of
  `public/1`, the same in every service.

  ## Examples

      "drivers_license" = KycCore.DocumentType.public("cnh")
  """
  @type value :: :cnh | :rg | :unknown
  @values [:cnh, :rg, :unknown]

  @spec all() :: [value(), ...]
  def all, do: @values

  @spec valid?(term()) :: boolean()
  def valid?(value), do: value in @values

  @doc """
  The name of a document type in API responses.

  ## Parameters
    - type: an internal type, as atom or string

  ## Returns
    - `"drivers_license"`, `"id_card"` or `"unknown"`
  """
  @spec public(atom() | String.t()) :: String.t()
  def public(type) when type in [:cnh, "cnh"], do: "drivers_license"
  def public(type) when type in [:rg, "rg"], do: "id_card"
  def public(_type), do: "unknown"
end
