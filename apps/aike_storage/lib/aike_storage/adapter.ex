defmodule AikeStorage.Adapter do
  @moduledoc """
  Behaviour for blob storage adapters.

  An adapter stores, reads and deletes objects by key. `AikeStorage.Adapter.Local`,
  `AikeStorage.Adapter.S3` and `AikeStorage.Adapter.Fake` implement it.
  """
  @callback put(binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, term()}
end
