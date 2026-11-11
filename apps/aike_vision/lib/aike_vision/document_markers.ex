defmodule AikeVision.DocumentMarkers do
  @moduledoc """
  Brazilian document type rules on recognized text, shared by classification and
  extraction.

  - CNH: its title ("CARTEIRA NACIONAL DE HABILITAÇÃO") with "BRASIL"
  - RG: its title with "BRASIL", or at least three markers printed only on the RG. The
    title sits in a small rotated box that OCR often misses. The law of the back
    ("LEI Nº 7.116") counts with or without its dot, which OCR often drops
  - Evidence of both types is a conflict, and the type stays unknown

  ## Properties
    - `type`: `:cnh`, `:rg` or `:unknown`
    - `rg_front` / `rg_back`: markers of the RG front or back were found
    - `digital`: the text shows a digital document ("ASSINADO DIGITALMENTE" or
      "CERTIFICADO DIGITAL")

  ## Examples

      %{type: :rg, rg_front: true, rg_back: true} =
        AikeVision.DocumentMarkers.analyze("IDENTIFICACAO LEI 7.116 DOC. ORIGEM NATURALIDADE")
  """

  @rg_front [
    "CARTEIRA DE IDENTIDADE",
    "SECRETARIA DA SEGURANCA PUBLICA",
    "IDENTIFICACAO",
    "POLEGAR DIREITO",
    "ASSINATURA DO TITULAR"
  ]
  @rg_back [
    "REGISTRO GERAL",
    ~r/\bLEI(?: NO?)? 7 ?116\b/,
    "DOC ORIGEM",
    "NATURALIDADE",
    "DATA DE EXPEDICAO",
    "ASSINATURA DO DIRETOR"
  ]
  @min_rg_markers 3

  @type t :: %{
          type: :cnh | :rg | :unknown,
          rg_front: boolean(),
          rg_back: boolean(),
          digital: boolean()
        }

  @doc """
  Analyzes recognized text. Accents, case and punctuation are ignored.

  ## Parameters
    - text: all the text read from the document

  ## Returns
    - the markers found, see the module properties
  """
  @spec analyze(String.t()) :: t()
  def analyze(text) do
    analyze_normalized(normalize(text))
  end

  defp marker?(text, %Regex{} = pattern), do: Regex.match?(pattern, text)
  defp marker?(text, marker), do: String.contains?(text, marker)

  defp analyze_normalized(normalized) do
    brasil = String.contains?(normalized, "BRASIL")
    rg_front = Enum.filter(@rg_front, &String.contains?(normalized, &1))
    rg_back = Enum.filter(@rg_back, &marker?(normalized, &1))

    cnh = brasil and String.contains?(normalized, "CARTEIRA NACIONAL DE HABILITACAO")

    rg =
      (brasil and "CARTEIRA DE IDENTIDADE" in rg_front) or
        length(rg_front ++ rg_back) >= @min_rg_markers

    %{
      type: type(cnh, rg),
      rg_front: rg_front != [],
      rg_back: rg_back != [],
      digital:
        String.contains?(normalized, "ASSINADO DIGITALMENTE") or
          String.contains?(normalized, "CERTIFICADO DIGITAL")
    }
  end

  defp type(true, false), do: :cnh
  defp type(false, true), do: :rg
  defp type(_, _), do: :unknown

  defp normalize(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]+/, " ")
  end
end
