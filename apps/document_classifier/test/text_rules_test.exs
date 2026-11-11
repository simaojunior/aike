defmodule DocumentClassifier.TextRulesTest do
  use ExUnit.Case, async: true
  alias DocumentClassifier.Engine.TextRules

  test "requires multiple signals and does not guess the side" do
    result =
      TextRules.classify("REPÚBLICA FEDERATIVA DO BRASIL CARTEIRA NACIONAL DE HABILITAÇÃO", 90)

    assert result["document"] == %{"type" => "cnh", "country" => "BR", "side" => "unknown"}
    assert result["quality"]["acceptable"]
    assert {:ok, _} = DocumentClassifier.Result.validate(result)
  end

  test "a digital CNH shows both sides" do
    for marker <- ["ASSINADO DIGITALMENTE", "Documento assinado com certificado digital"] do
      text = "REPÚBLICA FEDERATIVA DO BRASIL CARTEIRA NACIONAL DE HABILITAÇÃO " <> marker
      assert TextRules.classify(text, 90)["document"]["side"] == "single"
    end

    assert TextRules.classify("BRASIL CARTEIRA DE IDENTIDADE ASSINADO DIGITALMENTE", 90)[
             "document"
           ]["side"] == "front"
  end

  test "an RG without its title is recognized by its own markers and sides" do
    for {text, side} <- [
          {"IDENTIFICAÇÃO LEI Nº 7.116 DOC. ORIGEM NATURALIDADE", "single"},
          {"SECRETARIA DA SEGURANÇA PÚBLICA INSTITUTO DE IDENTIFICAÇÃO POLEGAR DIREITO", "front"},
          {"REGISTRO GERAL NATURALIDADE DOC. ORIGEM", "back"}
        ] do
      assert TextRules.classify(text, 90)["document"] == %{
               "type" => "rg",
               "country" => "BR",
               "side" => side
             }
    end

    assert TextRules.classify("NATURALIDADE DOC. ORIGEM", 90)["document"]["type"] == "unknown"
  end

  test "weak, foreign and conflicting evidence stays unknown" do
    for text <- [
          "CNH",
          "driver license",
          "BRASIL CARTEIRA NACIONAL DE HABILITACAO CARTEIRA DE IDENTIDADE",
          "BRASIL CARTEIRA NACIONAL DE HABILITACAO REGISTRO GERAL NATURALIDADE DOC ORIGEM"
        ] do
      assert TextRules.classify(text, 90)["document"]["type"] == "unknown"
    end
  end

  test "poor text recognition does not approve quality" do
    result = TextRules.classify("BRASIL CARTEIRA DE IDENTIDADE", 20)
    refute result["quality"]["acceptable"]
    assert "low_text_confidence" in result["quality"]["issues"]
  end

  test "image issues make a readable document unacceptable" do
    text = "REPÚBLICA FEDERATIVA DO BRASIL CARTEIRA NACIONAL DE HABILITAÇÃO"
    result = TextRules.classify(text, 90, ["low_resolution"])
    refute result["quality"]["acceptable"]
    assert result["quality"]["issues"] == ["low_resolution"]
  end

  test "empty text is unknown and unacceptable" do
    result = TextRules.classify("", 0)
    assert result["document"]["type"] == "unknown"
    refute result["quality"]["acceptable"]
  end
end
