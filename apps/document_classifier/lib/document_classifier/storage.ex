defmodule DocumentClassifier.Storage do
  @moduledoc """
  Behaviour for reading stored images in the classifier service.

  An implementation returns the bytes that belong to a key.
  """
  @callback get(String.t()) :: {:ok, binary()} | {:error, term()}
end
