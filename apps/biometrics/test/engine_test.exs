defmodule Biometrics.EngineTest do
  use ExUnit.Case, async: true

  test "fake engine returns a successful match" do
    assert {:ok, %{"match" => true, "similarity_score" => 0.98}} =
             Biometrics.Engine.Fake.compare("selfie", "document", [])
  end
end
