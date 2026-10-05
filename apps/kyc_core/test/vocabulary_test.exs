defmodule KycCore.VocabularyTest do
  use ExUnit.Case, async: true

  test "shared vocabulary" do
    for module <- [
          KycCore.DocumentType,
          KycCore.DocumentSide,
          KycCore.Country,
          KycCore.DocumentStatus
        ] do
      for value <- module.all(), do: assert(module.valid?(value))
      refute module.valid?(:invalid)
      refute module.valid?(nil)
    end
  end
end
