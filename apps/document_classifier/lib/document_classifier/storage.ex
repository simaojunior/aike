defmodule DocumentClassifier.Storage do
  @callback get(String.t()) :: {:ok, binary()} | {:error, term()}
end
