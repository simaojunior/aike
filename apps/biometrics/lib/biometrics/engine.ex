defmodule Biometrics.Engine do
  @moduledoc """
  Behaviour for face comparison engines.

  An engine receives the bytes of two images and returns the comparison result.
  """
  @callback compare(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
end
