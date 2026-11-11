defmodule DocumentOcr.CNHLabelsTest do
  use ExUnit.Case, async: true
  alias DocumentOcr.Extraction.CNHLabels
  alias DocumentOcr.Validation

  defp line(text, left, top, opts \\ []) do
    %{
      "text" => text,
      "confidence" => Keyword.get(opts, :confidence, 0.95),
      "bbox" => [left, top, 300, Keyword.get(opts, :height, 30)],
      "source" => Keyword.get(opts, :source, 0)
    }
  end

  defp card(source, cpf \\ "529.982.247-25", confidence \\ 0.95) do
    [
      line("NOME", 340, 340, source: source),
      line("NARUTO UZUMAKI", 332, 400, source: source, confidence: confidence),
      line("CPF", 990, 615, source: source),
      line("DATA NASCIMENTO", 1500, 615, source: source),
      line("| #{cpf} |", 955, 626, source: source, height: 70, confidence: confidence),
      line("12/03/1990", 1485, 663, source: source, confidence: confidence)
    ]
  end

  test "reads each value below its label and normalizes it" do
    assert {:ok, %{"document" => %{"type" => "cnh"}, "fields" => person}} =
             CNHLabels.extract(%{"text" => card(0)})

    assert person["full_name"]["value"] == "NARUTO UZUMAKI"
    assert person["cpf"]["value"] == "52998224725"
    assert person["cpf"]["raw_value"] == "529.982.247-25"
    assert person["birth_date"]["value"] == "1990-03-12"

    result = Validation.validate_result(%{"document" => %{"type" => "cnh"}, "fields" => person})
    assert Validation.outcome(result) == :completed
  end

  test "a valid CPF from another pass wins over a misread one" do
    lines = card(0, "529.982.247-26", 0.99) ++ card(1, "529.982.247-25", 0.80)
    {:ok, %{"fields" => person}} = CNHLabels.extract(%{"text" => lines})
    assert person["cpf"]["value"] == "52998224725"
    assert person["cpf"]["confidence"] == 0.80
  end

  test "the registration number starts under \"Nº\", left of the word REGISTRO" do
    lines = card(0) ++ [line("Nº REGISTRO", 341, 1232), line("52998224725", 332, 1270)]
    {:ok, %{"fields" => fields}} = CNHLabels.extract(%{"text" => lines})
    assert fields["registration_number"]["value"] == "52998224725"

    without_number_sign =
      card(0) ++ [line("REGISTRO", 400, 1232), line("52998224725", 395, 1270)]

    {:ok, %{"fields" => fields}} = CNHLabels.extract(%{"text" => without_number_sign})
    assert fields["registration_number"]["value"] == "52998224725"
  end

  test "geometry is compared only inside one OCR pass" do
    lines = [line("NOME", 340, 340, source: 0), line("NARUTO UZUMAKI", 332, 400, source: 1)]
    {:ok, %{"fields" => person}} = CNHLabels.extract(%{"text" => lines})
    assert person["full_name"]["value"] == nil
  end

  test "a missing field is rejected by validation instead of failing extraction" do
    lines = Enum.reject(card(0), &(&1["text"] == "12/03/1990"))
    {:ok, %{"fields" => person} = result} = CNHLabels.extract(%{"text" => lines})
    assert person["birth_date"]["value"] == nil
    assert Validation.outcome(Validation.validate_result(result)) == :rejected
  end

  test "malformed OCR output is an error" do
    for raw <- [
          %{},
          %{"text" => []},
          %{"text" => [%{"text" => "NOME", "confidence" => 0.9}]},
          %{"text" => [%{line("NOME", 0, 0) | "confidence" => 90}]}
        ] do
      assert {:error, :invalid_ocr_output} = CNHLabels.extract(raw)
    end
  end
end
