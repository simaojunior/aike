defmodule Biometrics.InputValidationTest do
  use ExUnit.Case, async: true
  alias BiometricsWeb.Schemas.FacematchParams

  test "file paths and JSON objects cannot substitute multipart uploads" do
    params = %{
      "externalId" => "fixture",
      "selfieImage" => "/private/path",
      "documentImage" => %{}
    }

    assert {:error, errors} = FacematchParams.create(params)
    assert Enum.all?(errors, &match?(%Peri.Error{}, &1))

    assert Enum.map(AikeHttp.FieldIssues.from_peri(errors), & &1.field) == [
             "documentImage",
             "selfieImage"
           ]
  end
end
