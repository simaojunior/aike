defmodule DocumentClassifier.Engine do
  @moduledoc "Stateless classification contract. Confidence and image quality are independent."
  @callback classify(binary(), keyword()) :: {:ok, map()} | {:error, term()}
end
