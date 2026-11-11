defmodule KycCore.JsonKeyFormatter do
  @moduledoc """
  Converts map keys between the API (camelCase) and the code (snake_case).

  Requests arrive in camelCase and are parsed to snake_case after validation (`parse/1`);
  responses are built in snake_case and formatted to camelCase (`format/1`). Values are
  never changed.

  ## Examples

      %{"selfieImage" => _} = KycCore.JsonKeyFormatter.format(%{selfie_image: upload})
      %{"selfie_image" => _} = KycCore.JsonKeyFormatter.parse(%{"selfieImage" => upload})
  """

  @doc """
  Recursively converts map keys in maps and lists to camelCase.

  Scalar values and structs (such as `DateTime`) are returned unchanged, so the helper
  can be applied to a full response tree.
  """
  @spec format(term()) :: term()
  def format(%_{} = struct), do: struct

  def format(data) when is_map(data) do
    Map.new(data, fn {key, value} -> {to_camel_case(key), format(value)} end)
  end

  def format(data) when is_list(data), do: Enum.map(data, &format/1)
  def format(data), do: data

  @doc """
  Recursively converts map keys in maps and lists to snake_case strings.

  Structs (such as `Plug.Upload`) and values are returned unchanged.

  ## Parameters
    - data: validated request parameters

  ## Returns
    - the same tree with snake_case keys
  """
  @spec parse(term()) :: term()
  def parse(%_{} = struct), do: struct

  def parse(data) when is_map(data) do
    Map.new(data, fn {key, value} -> {to_snake_case(key), parse(value)} end)
  end

  def parse(data) when is_list(data), do: Enum.map(data, &parse/1)
  def parse(data), do: data

  @doc """
  Converts one camelCase key to snake_case.

  ## Parameters
    - key: a string or atom key, such as `"selfieImage"`

  ## Returns
    - the snake_case string, such as `"selfie_image"`
  """
  @spec to_snake_case(atom() | String.t()) :: String.t()
  def to_snake_case(key) when is_atom(key), do: key |> Atom.to_string() |> to_snake_case()
  def to_snake_case(key) when is_binary(key), do: Macro.underscore(key)

  @spec to_camel_case(atom() | String.t()) :: String.t()
  def to_camel_case(key) when is_atom(key), do: key |> Atom.to_string() |> to_camel_case()

  def to_camel_case(key) when is_binary(key) do
    case String.split(key, "_") do
      [head | tail] -> Enum.join([head | Enum.map(tail, &String.capitalize/1)])
      [] -> key
    end
  end
end
