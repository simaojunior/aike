defmodule AikeStorage.Adapter do
  @callback put(binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, term()}
end
