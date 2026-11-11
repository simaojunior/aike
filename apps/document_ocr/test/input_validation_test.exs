defmodule DocumentOcr.InputValidationTest do
  use ExUnit.Case, async: true
  alias DocumentOcrWeb.Schemas.DocumentParams

  test "field errors name the camelCase input field" do
    assert {:error, errors} =
             DocumentParams.create(%{
               "externalId" => "",
               "documentType" => "passport",
               "file" => nil
             })

    fields = errors |> AikeHttp.FieldIssues.from_peri() |> Enum.map(& &1.field) |> Enum.sort()
    assert fields == ["documentType", "externalId", "file"]
  end

  test "Peri validates nested image fields and cardinality before ingestion" do
    params = %{
      "externalId" => "fixture",
      "documentType" => "cnh",
      "country" => "BR",
      "images" => [%{"side" => "front", "image" => "!invalid!"}]
    }

    assert {:error, errors} = DocumentParams.create(params)
    assert Enum.all?(errors, &match?(%Peri.Error{}, &1))
    issues = AikeHttp.FieldIssues.from_peri(errors)
    assert Enum.any?(issues, &(&1.field == "images.0.image"))
    refute Jason.encode!(issues) =~ "!invalid!"

    for invalid <- [42, nil, "not-an-image"] do
      assert {:error, nested} = DocumentParams.create(%{params | "images" => [invalid]})
      assert [%{field: "images.0"}] = AikeHttp.FieldIssues.from_peri(nested)
    end

    assert {:error, _} = DocumentParams.create(%{params | "images" => []})
    image = %{"side" => "front", "image" => Base.encode64("bytes")}
    assert {:error, _} = DocumentParams.create(%{params | "images" => [image, image]})
    assert {:ok, _} = DocumentParams.create(%{params | "images" => [image]})
  end
end
