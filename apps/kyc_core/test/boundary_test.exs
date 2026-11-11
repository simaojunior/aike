defmodule KycCore.BoundaryTest do
  use ExUnit.Case, async: true

  test "core runtime dependencies are limited to Elixir and OTP" do
    dependencies = Application.spec(:kyc_core, :applications)
    assert dependencies -- [:kernel, :stdlib, :elixir, :crypto, :logger] == []
  end
end
