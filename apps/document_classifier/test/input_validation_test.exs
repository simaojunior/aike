defmodule DocumentClassifier.InputValidationTest do
  use ExUnit.Case, async: true
  alias DocumentClassifierWeb.Schemas.ClassificationParams

  test "JSON and multipart are validated by Peri, without repository or engine calls" do
    assert {:error, [%Peri.Error{} | _]} =
             ClassificationParams.create(%{"image" => %{private: "fixture"}})

    assert {:error, [%Peri.Error{} | _]} =
             ClassificationParams.create(%{"file" => "fake-file-path"})

    assert {:ok, %{"image" => _}} =
             ClassificationParams.create(%{"image" => Base.encode64("bytes")})
  end
end
