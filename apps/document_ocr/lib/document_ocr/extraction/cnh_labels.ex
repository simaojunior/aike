defmodule DocumentOcr.Extraction.CNHLabels do
  @moduledoc """
  Reads every field printed on a CNH (driver's license) by its label.

  See `DocumentOcr.Extraction.Labels`. The identity document box holds three values
  ("41311333 SSP SP": number, issuer and state). The issue place is a place name followed
  by its state.

  ## Fields
    - required: `full_name`, `cpf`, `birth_date`
    - optional, present only when read: `identity_number`, `identity_issuer`,
      `identity_state`, `fathers_name`, `mothers_name`, `category`,
      `registration_number`, `expiration_date`, `first_license_date`, `issue_place`,
      `issue_date`

  ## Examples

      {:ok, %{"document" => %{"type" => "cnh"}, "fields" => fields}} =
        DocumentOcr.Extraction.CNHLabels.extract(raw_ocr)
  """
  alias DocumentOcr.Extraction.{Filiation, Labels, Parsers}

  @states ~w(AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO)
  @category ~r/\A(ACC|AB|AC|AD|AE|A|B|C|D|E)\z/

  @doc """
  Extracts the CNH fields from OCR output.

  ## Parameters
    - raw: OCR engine output (see `DocumentOcr.Extraction.Labels.prepare/1`)

  ## Returns
    - `{:ok, %{"document" => ..., "fields" => ...}}`; a missing required field has a
      `nil` value and is rejected by validation
    - `{:error, :invalid_ocr_output}`
  """
  @spec extract(term()) :: {:ok, map()} | {:error, :invalid_ocr_output}
  def extract(raw) do
    with {:ok, lines} <- Labels.prepare(raw) do
      fields =
        %{
          "full_name" => Labels.best(Labels.below(lines, "NOME", &Parsers.name/1)),
          "cpf" => Labels.best(Labels.below(lines, "CPF", &Parsers.cpf/1)),
          "birth_date" => Labels.best(Labels.below(lines, "DATA NASCIMENTO", &Parsers.date/1))
        }
        |> put_identity(lines)
        |> then(&Filiation.put(lines, &1))
        |> Labels.put_found("category", Labels.below(lines, "CAT HAB", &category/1))
        |> Labels.put_found("registration_number", registration(lines))
        |> Labels.put_found("expiration_date", Labels.below(lines, "VALIDADE", &Parsers.date/1))
        |> Labels.put_found(
          "first_license_date",
          Labels.below(lines, "1 HABILITACAO", &Parsers.date/1)
        )
        |> Labels.put_found("issue_place", Labels.below(lines, "LOCAL", &place/1))
        |> Labels.put_found("issue_date", Labels.below(lines, "DATA EMISSAO", &Parsers.date/1))

      {:ok, %{"document" => %{"type" => "cnh", "country" => "BR"}, "fields" => fields}}
    end
  end

  defp registration(lines) do
    case Labels.below(lines, "N REGISTRO", Parsers.digits(9..11)) do
      [] -> Labels.below(lines, "REGISTRO", Parsers.digits(9..11))
      found -> found
    end
  end

  defp put_identity(fields, lines) do
    identities = Labels.below(lines, "DOC IDENTIDADE", &identity/1)

    fields
    |> Labels.put_found("identity_number", parts(identities, :number))
    |> Labels.put_found("identity_issuer", parts(identities, :issuer))
    |> Labels.put_found("identity_state", parts(identities, :state))
  end

  defp parts(identities, part) do
    for %{^part => value} = identity <- identities,
        value != nil,
        do: %{
          value: value,
          raw_value: identity.raw_value,
          valid: true,
          confidence: identity.confidence
        }
  end

  defp identity(text) do
    tokens = text |> String.upcase() |> String.split(~r/[\s\/]+/, trim: true)
    {state, rest} = trailing_state(tokens)

    case Enum.split_with(rest, &Regex.match?(~r/\d/, &1)) do
      {[], _} ->
        []

      {numbers, issuers} ->
        [
          %{
            number: numbers |> Enum.join() |> String.replace(~r/[^\dX]/, ""),
            issuer:
              issuers
              |> Enum.filter(&Regex.match?(~r/\A[A-Z]{2,10}\z/, &1))
              |> Enum.join(" ")
              |> blank(),
            state: state,
            raw_value: String.trim(text),
            valid: true
          }
        ]
    end
  end

  defp trailing_state(tokens) do
    case List.last(tokens) do
      state when state in @states and length(tokens) > 1 -> {state, Enum.drop(tokens, -1)}
      _ -> {nil, tokens}
    end
  end

  defp blank(""), do: nil
  defp blank(value), do: value

  defp category(text) do
    for token <- text |> String.upcase() |> String.split(~r/[^A-Z]+/, trim: true),
        Regex.match?(@category, token),
        do: %{value: token, raw_value: String.trim(text), valid: true}
  end

  defp place(text) do
    for candidate <- Parsers.text(text),
        Regex.match?(~r/[A-Z]{3,}/, candidate.value),
        do: candidate
  end
end
