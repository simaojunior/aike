defmodule DocumentOcr.RGLabelsTest do
  use ExUnit.Case, async: true
  alias DocumentOcr.Extraction.RGLabels
  alias DocumentOcr.Validation

  defp line(text, left, top, source \\ 0),
    do: %{
      "text" => text,
      "confidence" => 0.95,
      "bbox" => [left, top, 300, 30],
      "source" => source
    }

  defp back(extra) do
    [
      line("REGISTRO GERAL 1234567890", 40, 40),
      line("19/12/2018", 600, 40),
      line("NOME", 40, 100),
      line("NARUTO UZUMAKI", 40, 140)
    ] ++ extra
  end

  test "reads the RG number beside its label and the name below its label" do
    {:ok, %{"document" => %{"type" => "rg"}, "fields" => person}} =
      RGLabels.extract(%{"text" => back([line("12/03/1990", 600, 300)])})

    assert person["rg_number"]["value"] == "1234567890"
    assert person["full_name"]["value"] == "NARUTO UZUMAKI"
  end

  test "the RG number may also sit on the line below the label" do
    lines = [line("REGISTRO", 40, 40), line("12.345.678-9", 40, 80)]
    {:ok, %{"fields" => person}} = RGLabels.extract(%{"text" => lines})
    assert person["rg_number"]["value"] == "123456789"
    assert person["rg_number"]["raw_value"] == "12.345.678-9"
  end

  test "without the birth date label, the earliest of several dates is the birth date" do
    {:ok, %{"fields" => person}} =
      RGLabels.extract(%{"text" => back([line("12/03/1990", 600, 300)])})

    assert person["birth_date"]["value"] == "1990-03-12"
  end

  test "the labeled birth date wins over the earliest date" do
    lines = back([line("DATA DE NASCIMENTO", 600, 260), line("12/03/1995", 600, 300)])
    lines = lines ++ [line("01/01/1980", 40, 600)]
    {:ok, %{"fields" => person}} = RGLabels.extract(%{"text" => lines})
    assert person["birth_date"]["value"] == "1995-03-12"
  end

  test "a single unlabeled date is not guessed and goes to review" do
    {:ok, %{"fields" => person} = result} = RGLabels.extract(%{"text" => back([])})
    assert person["birth_date"]["value"] == nil
    assert Validation.outcome(Validation.validate_result(result)) == :rejected
  end

  test "CPF is present only when the card prints one" do
    {:ok, %{"fields" => without}} =
      RGLabels.extract(%{"text" => back([line("12/03/1990", 600, 300)])})

    refute Map.has_key?(without, "cpf")

    {:ok, %{"fields" => with_label}} =
      RGLabels.extract(%{
        "text" =>
          back([
            line("12/03/1990", 600, 300),
            line("CPF", 40, 400),
            line("529.982.247-25", 40, 440)
          ])
      })

    assert with_label["cpf"]["value"] == "52998224725"

    {:ok, %{"fields" => unlabeled}} =
      RGLabels.extract(%{
        "text" => back([line("12/03/1990", 600, 300), line("529.982.247-25", 40, 700)])
      })

    assert unlabeled["cpf"]["value"] == "52998224725"

    {:ok, %{"fields" => invalid}} =
      RGLabels.extract(%{
        "text" => back([line("12/03/1990", 600, 300), line("529.982.247-26", 40, 700)])
      })

    refute Map.has_key?(invalid, "cpf")
  end

  test "malformed OCR output is an error" do
    assert {:error, :invalid_ocr_output} = RGLabels.extract(%{"text" => []})
    assert {:error, :invalid_ocr_output} = RGLabels.extract(%{"text" => [%{"text" => "NOME"}]})
  end
end
