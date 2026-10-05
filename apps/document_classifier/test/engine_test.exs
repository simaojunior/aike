defmodule DocumentClassifier.EngineTest do
  use ExUnit.Case, async: true
  alias DocumentClassifier.{Engine, Result}

  test "default fake response matches the API contract" do
    assert {:ok,
            %{
              "document" => %{"type" => "cnh", "country" => "BR", "side" => "front"},
              "quality" => %{"acceptable" => true, "score" => 0.96, "issues" => []},
              "confidence" => 0.99
            }} = Engine.Fake.classify("arbitrary-image-bytes", [])
  end

  test "fake fixtures cover type and side vocabulary" do
    for {bytes, type, side} <- [
          {"fake:cnh_back", "cnh", "back"},
          {"fake:rg_front", "rg", "front"},
          {"fake:rg_back", "rg", "back"},
          {"fake:rg_single", "rg", "single"},
          {"fake:unknown", "unknown", "unknown"}
        ] do
      assert {:ok, result} = Engine.Fake.classify(bytes, [])
      assert result["document"] == %{"type" => type, "country" => "BR", "side" => side}
      assert {:ok, ^result} = Result.validate(result)
    end
  end

  test "unknown and poor quality have independent confidence and quality scores" do
    {:ok, unknown} = Engine.Fake.classify("fake:unknown", [])
    assert unknown["confidence"] == 0.37
    assert unknown["quality"] == %{"acceptable" => true, "score" => 0.91, "issues" => []}
    {:ok, bad} = Engine.Fake.classify("fake:bad_quality", [])
    assert bad["confidence"] == 0.98

    assert bad["quality"] == %{
             "acceptable" => false,
             "score" => 0.42,
             "issues" => ["blur", "glare"]
           }
  end

  test "engine boundary rejects invalid vocabulary, scores and field types" do
    {:ok, valid} = Engine.Fake.classify("bytes", [])

    for invalid <- [
          %{},
          nil,
          put_in(valid, ["document", "type"], "passport"),
          put_in(valid, ["document", "country"], "US"),
          put_in(valid, ["document", "side"], "left"),
          put_in(valid, ["confidence"], 1.1),
          put_in(valid, ["confidence"], -0.1),
          put_in(valid, ["confidence"], "0.99"),
          put_in(valid, ["quality", "score"], nil),
          put_in(valid, ["quality", "score"], 1.1),
          put_in(valid, ["quality", "acceptable"], "true"),
          put_in(valid, ["quality", "issues"], "blur"),
          put_in(valid, ["quality", "issues"], [42])
        ] do
      assert {:error, :invalid_engine_result} = Result.validate(invalid)
    end
  end

  test "only documented engine fields cross the HTTP boundary" do
    {:ok, result} = Engine.Fake.classify("bytes", [])

    augmented =
      result |> Map.put("raw_image", "sensitive") |> put_in(["document", "debug"], "sensitive")

    assert {:ok, ^result} = Result.validate(augmented)
  end
end
