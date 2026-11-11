defmodule DocumentOcr.Storage do
  @moduledoc """
  Behaviour for reading stored document images.

  An implementation returns the bytes that belong to a key.
  """
  @callback get(String.t()) :: {:ok, binary()} | {:error, term()}
end
