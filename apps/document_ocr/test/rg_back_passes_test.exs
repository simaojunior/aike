defmodule DocumentOcr.RGBackPassesTest do
  use ExUnit.Case, async: true
  alias DocumentOcr.Extraction.RGLabels

  defp line(text, left, top, width, source),
    do: %{
      "text" => text,
      "confidence" => 0.9,
      "bbox" => [left, top, width, 40],
      "source" => source
    }

  defp sp_back do
    [
      line("REGISTRO D ATA D", 310, 296, 400, "0:0.3"),
      line("NOME", 230, 484, 120, "0:0.3"),
      line("ISENARUTO UZUMAKI", 230, 533, 700, "0:0.3"),
      line("NATURALIDADE", 333, 872, 300, "0:0.3"),
      line("A - SP", 373, 952, 130, "0:0.3"),
      line("DOC ORIGEM", 339, 1089, 260, "0:0.3"),
      line("KONOHA CN LV.A040 FLS 12 N 345", 298, 1139, 1050, "0:0.3"),
      line("CcPF", 348, 1299, 74, "0:0.3"),
      line("529982247/25 1 Robe", 308, 1340, 1290, "0:0.3"),
      line("PRNARUTO UZUMAKI", 240, 533, 700, "0:0.0"),
      line("NARUTO UZUMAKI", 250, 533, 680, "0:0.1"),
      line("KONOHA - SP", 300, 932, 276, "0:0.1"),
      line("12.345.678-9 2via", 510, 346, 700, "0:0.2"),
      line("NARUTO UZUMAKI", 286, 533, 650, "0:0.2"),
      line("KONOHA - SP", 294, 948, 212, "0:0.2"),
      line("12/03/1990", 1662, 907, 398, "0:0.2"),
      line("19/12/2018", 1569, 310, 321, "0:0.2")
    ]
  end

  test "a label read in one pass finds the value in every pass of the same image" do
    {:ok, %{"fields" => fields}} = RGLabels.extract(%{"text" => sp_back()})
    assert fields["full_name"]["value"] == "NARUTO UZUMAKI"
    assert fields["birthplace"]["value"] == "KONOHA - SP"
  end

  test "the RG number in the Sao Paulo format is read without its label" do
    {:ok, %{"fields" => fields}} = RGLabels.extract(%{"text" => sp_back()})
    assert fields["rg_number"]["value"] == "123456789"
    assert fields["rg_number"]["raw_value"] == "12.345.678-9"
  end

  test "the CPF printed as nine digits, slash and check digits is read" do
    {:ok, %{"fields" => fields}} = RGLabels.extract(%{"text" => sp_back()})
    assert fields["cpf"]["value"] == "52998224725"
  end

  test "the origin document stops at a misread CPF label" do
    {:ok, %{"fields" => fields}} = RGLabels.extract(%{"text" => sp_back()})
    refute fields["origin_document"]["value"] =~ "CPF"
    assert fields["origin_document"]["value"] =~ "KONOHA"
  end

  test "an old-format CPF with wrong check digits is not read" do
    lines =
      sp_back()
      |> Enum.map(
        &Map.update!(&1, "text", fn t -> String.replace(t, "529982247/25", "529982247/26") end)
      )

    {:ok, %{"fields" => fields}} = RGLabels.extract(%{"text" => lines})
    refute Map.has_key?(fields, "cpf")
  end

  test "passes of another image of the same upload are never mixed" do
    lines = [
      line("NOME", 230, 484, 120, "0:0.3"),
      line("SASUKE UCHIHA", 250, 533, 650, "0:1.1")
    ]

    {:ok, %{"fields" => fields}} = RGLabels.extract(%{"text" => lines})
    assert fields["full_name"]["value"] == nil
  end

  test "a number glued to a misread letter is not the RG number, even with more votes" do
    lines =
      sp_back() ++
        [
          line("S A2.345.678-9 2 ia", 435, 332, 774, "0:0.0"),
          line("T A2.345.678-9 2 via", 436, 309, 1454, "0:0.1")
        ]

    {:ok, %{"fields" => fields}} = RGLabels.extract(%{"text" => lines})
    assert fields["rg_number"]["value"] == "123456789"
  end

  test "a birthplace needs a word of at least three letters" do
    lines =
      sp_back() ++
        [line("- SP", 333, 932, 120, "0:0.0"), line("- SP", 333, 934, 120, "0:0.4")]

    {:ok, %{"fields" => fields}} = RGLabels.extract(%{"text" => lines})
    assert fields["birthplace"]["value"] == "KONOHA - SP"
  end
end
