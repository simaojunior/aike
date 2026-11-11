defmodule DocumentOcr.ValidationTest do
  use ExUnit.Case, async: true
  alias DocumentOcr.{Validation, OCR}

  test "CPF normalization and checksum" do
    assert {:ok, "52998224725"} = Validation.validate_cpf("529.982.247-25")

    for value <- ["12345678900", "11111111111", "", nil, "5299822472x"] do
      assert {:error, :invalid_cpf} = Validation.validate_cpf(value)
    end
  end

  test "dates" do
    assert {:ok, "1990-03-12"} = Validation.validate_date("1990-03-12")
    assert {:error, :invalid_date} = Validation.validate_date("1990-02-30")
  end

  test "fake extraction preserves source, normalizes and validates fields" do
    {:ok, raw} = OCR.Fake.extract("bytes", [])
    {:ok, result} = DocumentOcr.Extraction.CNH.extract(raw)
    assert result["fields"]["birth_date"]["value"] == "1990-03-12"
    assert result["fields"]["cpf"]["raw_value"] == "529.982.247-25"
    assert Validation.outcome(Validation.validate_result(result)) == :completed

    bad =
      put_in(result, ["fields", "cpf", "value"], "12345678900") |> Validation.validate_result()

    assert bad["fields"]["cpf"]["status"] == "rejected"
    assert Validation.outcome(bad) == :rejected
    low = put_in(result, ["fields", "cpf", "confidence"], 0.65) |> Validation.validate_result()
    assert Validation.outcome(low) == :requires_confirmation
    assert low["fields"]["cpf"]["status"] == "requires_confirmation"
    assert {:error, :invalid_ocr_output} = DocumentOcr.Extraction.CNH.extract(%{})
  end

  test "extraction preserves corrupt CPF characters so validation rejects them" do
    {:ok, raw} = OCR.Fake.extract("bytes", [])
    [name, cpf, birth] = raw["text"]
    raw = %{"text" => [name, %{cpf | "text" => "X529.982.247-25"}, birth]}
    {:ok, extracted} = DocumentOcr.Extraction.CNH.extract(raw)
    result = Validation.validate_result(extracted)
    assert result["fields"]["cpf"]["raw_value"] == "X529.982.247-25"
    assert result["fields"]["cpf"]["status"] == "rejected"
    assert Validation.outcome(result) == :rejected
  end
end
