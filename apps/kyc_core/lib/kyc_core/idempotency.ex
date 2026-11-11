defmodule KycCore.Idempotency do
  @moduledoc "Deterministic fingerprints for idempotency identities."
  @spec fingerprint(term()) :: String.t()
  def fingerprint(value),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)
end
