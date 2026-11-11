defmodule KycCore.DocumentSide do
  @moduledoc """
  Sides shown in a document image: `:front`, `:back`, `:single` (both sides) or `:unknown`.

  API responses use the public names of `public/1`, the same in every service.

  ## Examples

      "front_and_back" = KycCore.DocumentSide.public("single")
  """
  @type value :: :front | :back | :single | :unknown
  @values [:front, :back, :single, :unknown]

  @spec all() :: [value(), ...]
  def all, do: @values

  @spec valid?(term()) :: boolean()
  def valid?(value), do: value in @values

  @doc """
  The name of a side in API responses.

  ## Parameters
    - side: an internal side, as atom or string

  ## Returns
    - `"only_front"`, `"only_back"`, `"front_and_back"` or `"unknown"`
  """
  @spec public(atom() | String.t()) :: String.t()
  def public(side) when side in [:front, "front"], do: "only_front"
  def public(side) when side in [:back, "back"], do: "only_back"
  def public(side) when side in [:single, "single"], do: "front_and_back"
  def public(_side), do: "unknown"
end
