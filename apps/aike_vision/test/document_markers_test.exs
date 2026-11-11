defmodule AikeVision.DocumentMarkersTest do
  use ExUnit.Case, async: true
  alias AikeVision.DocumentMarkers

  test "the RG back is recognized when the OCR reads the law number without its dot" do
    for law <- ["LEI Nº 7.116 DE 29/08/83", "LEI N 7116 DE 29/08/83", "LEI NO 7 116"] do
      assert %{type: :rg, rg_back: true, rg_front: false} =
               DocumentMarkers.analyze("NATURALIDADE KONOHAGAKURE DOC ORIGEM #{law}")
    end
  end

  test "the director's signature is a marker of the RG back" do
    assert %{type: :rg, rg_back: true} =
             DocumentMarkers.analyze("ASSINATURA DO DIRETOR NATURALIDADE DOC ORIGEM")
  end

  test "a number that only contains 7116 is not the law" do
    assert %{type: :unknown} =
             DocumentMarkers.analyze("NATURALIDADE DOC ORIGEM PROTOCOLO 871160")
  end

  test "text shared with the CNH does not make an RG" do
    assert %{type: :cnh} =
             DocumentMarkers.analyze(
               "REPUBLICA FEDERATIVA DO BRASIL CARTEIRA NACIONAL DE HABILITACAO " <>
                 "VALIDA EM TODO O TERRITORIO NACIONAL FILIACAO"
             )
  end
end
