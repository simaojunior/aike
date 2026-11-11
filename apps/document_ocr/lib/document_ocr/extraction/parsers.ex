defmodule DocumentOcr.Extraction.Parsers do
  @moduledoc """
  Turns the text read for a field into candidate values.

  Each parser returns a list: empty when the text holds no value of its kind, or one entry
  per value found, with the normalized `value`, the `raw_value` as read and whether it
  passes validation.

  ## Examples

      [%{value: "52998224725", valid: true}] = DocumentOcr.Extraction.Parsers.cpf("529.982.247-25")
      [%{value: "1990-03-12"}] = DocumentOcr.Extraction.Parsers.date("12/03/1990")
  """
  alias DocumentOcr.Validation

  @type candidate :: %{
          required(:value) => String.t(),
          required(:raw_value) => String.t(),
          required(:valid) => boolean(),
          optional(:confidence) => number()
        }
  @type parser :: (String.t() -> [candidate()])

  @cpf ~r/\d{3}[.,]?\d{3}[.,]?\d{3}\s*[-–—]?\s*\d{2}/u
  @formatted_cpf ~r/\d{3}\.\d{3}\.\d{3}-\d{2}/
  @slashed_cpf ~r/(?<!\d)\d{9}\/\d{2}(?!\d)/
  @sp_rg ~r/(?<![\w.])\d{1,2}\.\d{3}\.\d{3}-[\dXx](?![\d])/u
  @date ~r/(\d{2})\/(\d{2})\/(\d{4})/

  @doc """
  A person's name: letters only, at least two words, in upper case.

  ## Parameters
    - text: the text read

  ## Returns
    - `[candidate]` or `[]`
  """
  @spec name(String.t()) :: [candidate()]
  def name(text) do
    value =
      text
      |> String.replace(~r/[^\p{L}\s']/u, " ")
      |> String.split()
      |> Enum.filter(&(String.length(&1) >= 2))
      |> Enum.join(" ")
      |> String.upcase()

    found(length(String.split(value)) >= 2, value, text)
  end

  @doc """
  Free text such as a place: letters, digits and separators, at least three characters.

  ## Parameters
    - text: the text read

  ## Returns
    - `[candidate]` or `[]`
  """
  @spec text(String.t()) :: [candidate()]
  def text(text) do
    value =
      text
      |> String.replace(~r/[^\p{L}\d\s,\/.-]/u, " ")
      |> String.split()
      |> Enum.join(" ")
      |> String.trim(" ,.-")
      |> String.upcase()

    found(String.length(value) >= 3, value, text)
  end

  @doc """
  CPF numbers, with or without separators; `valid` follows the check digits.

  ## Parameters
    - text: the text read

  ## Returns
    - one candidate per number found; `value` has digits only
  """
  @spec cpf(String.t()) :: [candidate()]
  def cpf(text), do: cpfs(@cpf, text)

  @doc """
  CPF numbers printed as `000.000.000-00` with valid check digits only.

  Used without a label, so other numbers on the card cannot pass as a CPF.

  ## Parameters
    - text: the text read

  ## Returns
    - one candidate per valid CPF found
  """
  @spec formatted_cpf(String.t()) :: [candidate()]
  def formatted_cpf(text), do: cpfs(@formatted_cpf, text) |> Enum.filter(& &1.valid)

  @doc """
  CPF numbers printed as `000000000/00`, as older RGs from São Paulo print them, with
  valid check digits only.

  ## Parameters
    - text: the text read

  ## Returns
    - one candidate per valid CPF found
  """
  @spec slashed_cpf(String.t()) :: [candidate()]
  def slashed_cpf(text), do: cpfs(@slashed_cpf, text) |> Enum.filter(& &1.valid)

  @doc """
  RG numbers in the São Paulo format `00.000.000-0` (the last character may be `X`).

  The dots and the dash make the format distinctive enough to read without a label; a
  formatted CPF (`000.000.000-00`) never matches. A number glued to a letter is refused:
  it is usually a digit misread as a letter ("A7.358..." for "47.358..."), and the rest
  would be a wrong, shorter number.

  ## Parameters
    - text: the text read

  ## Returns
    - one candidate per RG number found; `value` has the digits only
  """
  @spec sp_rg(String.t()) :: [candidate()]
  def sp_rg(text) do
    for [raw] <- Regex.scan(@sp_rg, text),
        do: %{
          value: raw |> String.replace(~r/[.\-]/, "") |> String.upcase(),
          raw_value: raw,
          valid: true
        }
  end

  @doc """
  Dates printed as `DD/MM/YYYY`; `value` is ISO 8601 and `valid` checks the calendar.

  ## Parameters
    - text: the text read

  ## Returns
    - one candidate per date found
  """
  @spec date(String.t()) :: [candidate()]
  def date(text) do
    for [raw, day, month, year] <- Regex.scan(@date, text) do
      value = "#{year}-#{month}-#{day}"
      %{value: value, raw_value: raw, valid: match?({:ok, _}, Validation.validate_date(value))}
    end
  end

  @doc """
  Builds a parser for document numbers: digits with optional dots, dashes or spaces.

  ## Parameters
    - lengths: the accepted number of digits, such as `9..11`

  ## Returns
    - a parser; its candidates have digits (and a final `X`) only

  ## Example

      [%{value: "52998224725"}] = DocumentOcr.Extraction.Parsers.digits(9..11).("52998224725")
  """
  @spec digits(Range.t()) :: parser()
  def digits(lengths) do
    fn text ->
      for [raw] <- Regex.scan(~r/(?<![\d\/])\d[\d.\- ]{3,16}[\dXx](?![\d\/])/, text),
          value = raw |> String.replace(~r/[.\- ]/, "") |> String.upcase(),
          String.length(value) in lengths,
          do: %{value: value, raw_value: String.trim(raw), valid: true}
    end
  end

  defp found(true, value, text), do: [%{value: value, raw_value: String.trim(text), valid: true}]
  defp found(false, _value, _text), do: []

  defp cpfs(pattern, text) do
    for [raw] <- Regex.scan(pattern, text) do
      value = String.replace(raw, ~r/\D/, "")
      %{value: value, raw_value: raw, valid: match?({:ok, _}, Validation.validate_cpf(value))}
    end
  end
end
