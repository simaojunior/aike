defmodule Biometrics.Engine do
  @callback compare(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
end
