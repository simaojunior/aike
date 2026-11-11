defmodule Biometrics.DecisionTest do
  use ExUnit.Case, async: false
  alias Biometrics.Decision

  setup do
    original = Application.get_env(:biometrics, :decision)
    Application.put_env(:biometrics, :decision, approve_at: 0.5, review_at: 0.363)
    on_exit(fn -> Application.put_env(:biometrics, :decision, original) end)
  end

  test "splits similarity into approved, manual review and rejected" do
    assert Decision.decide(0.91) == %{matched: true, decision: "approved"}
    assert Decision.decide(0.5) == %{matched: true, decision: "approved"}
    assert Decision.decide(0.41) == %{matched: true, decision: "manual_review"}
    assert Decision.decide(0.363) == %{matched: true, decision: "manual_review"}
    assert Decision.decide(0.2) == %{matched: false, decision: "rejected"}
  end

  test "without a similarity, because a face is missing, the match is rejected" do
    assert Decision.decide(nil) == %{matched: false, decision: "rejected"}
  end
end
