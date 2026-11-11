defmodule Backoffice.ScopesTest do
  use ExUnit.Case, async: true
  alias Backoffice.Scopes

  test "scope wildcards match one segment as in Oke" do
    assert Scopes.granted?("users.read", ["users.*"])
    refute Scopes.granted?("users.sessions.revoke", ["users.*"])
    refute Scopes.granted?("companies.create", ["users.*"])
    refute Scopes.granted?("users.read", [])
  end

  test "roles resolve to explicit least-privilege scopes" do
    assert "companies.create" in Scopes.for_role("platform_admin")
    refute "companies.create" in Scopes.for_role("company_admin")
    assert "users.create" in Scopes.for_role("company_admin")
    refute "users.create" in Scopes.for_role("company_user")
    assert Scopes.for_role("untrusted") == []
  end
end
