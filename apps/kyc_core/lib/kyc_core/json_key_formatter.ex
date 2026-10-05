defmodule KycCore.JsonKeyFormatter do
  @moduledoc "Converts internal snake_case maps to camelCase API payloads."

  @doc """
  Recursively converts map keys in maps and lists to camelCase.

  Scalar values are returned unchanged so the helper can be applied to a full
  response tree without special handling for nested values.
  """
  @spec format(term()) :: term()
  def format(data) when is_map(data) do
    Map.new(data, fn {key, value} -> {to_camel_case(key), format(value)} end)
  end

  def format(data) when is_list(data), do: Enum.map(data, &format/1)
  def format(data), do: data

  @spec to_camel_case(atom() | String.t()) :: String.t()
  def to_camel_case(key) when is_atom(key), do: key |> Atom.to_string() |> to_camel_case()

  def to_camel_case(key) when is_binary(key) do
    case String.split(key, "_") do
      [head | tail] -> Enum.join([head | Enum.map(tail, &String.capitalize/1)])
      [] -> key
    end
  end
end
