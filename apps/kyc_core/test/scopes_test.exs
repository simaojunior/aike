defmodule KycCore.Auth.ScopesTest do
  use ExUnit.Case, async: true

  alias KycCore.Auth.Scopes

  test "includes independent classifier read and write scopes" do
    assert "classifier:write" in Scopes.all()
    assert "classifier:read" in Scopes.all()
    assert Scopes.valid?("classifier:write")
    assert Scopes.valid?("classifier:read")
  end

  test "does not treat OCR scope as classifier scope" do
    refute Scopes.valid?("classifier:delete")
    refute "classifier:write" in ["ocr:write"]
  end
end
