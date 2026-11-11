defmodule DocumentOcr.Extraction.RGLabels do
  @moduledoc """
  Reads every field printed on the back of an RG (identity card, older model).

  See `DocumentOcr.Extraction.Labels`. The RG number is printed beside the
  "REGISTRO GERAL" label, or below it; the São Paulo format (`00.000.000-0`) is read on
  any line and wins over a labeled reading that does not match it. The birth and issue
  date labels are tiny and pale:
  without them, and with two or more dates on the card, the earliest date is the birth
  date and the latest the issue date, because an RG is always issued after birth. With one
  unlabeled date, neither is guessed. Older RGs do not print the CPF; some from São Paulo
  print it as `000000000/00`.

  ## Fields
    - required: `full_name`, `rg_number`, `birth_date`
    - optional, present only when read: `issue_date`, `fathers_name`, `mothers_name`,
      `birthplace`, `origin_document`, `cpf`

  ## Examples

      {:ok, %{"document" => %{"type" => "rg"}, "fields" => fields}} =
        DocumentOcr.Extraction.RGLabels.extract(raw_ocr)
  """
  alias DocumentOcr.Extraction.{Filiation, Labels, Parsers}

  @doc """
  Extracts the RG fields from OCR output.

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
      dates = Labels.anywhere(lines, &Parsers.date/1) |> Enum.filter(& &1.valid)

      fields =
        %{
          "full_name" => Labels.best(Labels.below(lines, "NOME", &Parsers.name/1)),
          "rg_number" => Labels.best(rg_number(lines)),
          "birth_date" =>
            Labels.best(
              labeled_or(lines, ["DATA DE NASCIMENTO", "NASCIMENTO"], &earliest/1, dates)
            )
        }
        |> Labels.put_found(
          "issue_date",
          labeled_or(lines, ["DATA DE EXPEDICAO", "EXPEDICAO"], &latest/1, dates)
        )
        |> then(&Filiation.put(lines, &1))
        |> Labels.put_found("birthplace", Labels.below(lines, "NATURALIDADE", &place/1))
        |> Labels.put_found("origin_document", origin_document(lines))
        |> Labels.put_found(
          "cpf",
          Labels.below(lines, "CPF", &Parsers.cpf/1) ++
            Labels.anywhere(lines, &Parsers.formatted_cpf/1) ++
            Labels.anywhere(lines, &Parsers.slashed_cpf/1)
        )

      {:ok, %{"document" => %{"type" => "rg", "country" => "BR"}, "fields" => fields}}
    end
  end

  defp rg_number(lines) do
    number = Parsers.digits(5..14)

    labeled =
      Labels.right_of(lines, "REGISTRO GERAL", number) ++
        Labels.right_of(lines, "GERAL", number) ++ Labels.below(lines, "REGISTRO", number)

    sp_or_labeled(Labels.anywhere(lines, &Parsers.sp_rg/1), labeled)
  end

  defp place(text) do
    for candidate <- Parsers.text(text),
        Regex.match?(~r/\p{L}{3,}/u, candidate.value),
        do: candidate
  end

  defp sp_or_labeled([], labeled), do: labeled

  defp sp_or_labeled(sp, labeled) do
    values = MapSet.new(sp, & &1.value)
    sp ++ Enum.filter(labeled, &MapSet.member?(values, &1.value))
  end

  defp labeled_or(lines, labels, pick, dates) do
    labels
    |> Enum.find_value([], &labeled(lines, &1))
    |> or_picked(pick, dates)
  end

  defp labeled(lines, label) do
    case Labels.below(lines, label, &Parsers.date/1) ++
           Labels.right_of(lines, label, &Parsers.date/1) do
      [] -> nil
      found -> found
    end
  end

  defp or_picked([], pick, dates), do: pick.(dates)
  defp or_picked(labeled, _pick, _dates), do: labeled

  defp earliest(dates), do: pick_date(dates, &Enum.min/1)
  defp latest(dates), do: pick_date(dates, &Enum.max/1)

  defp pick_date(dates, choose) do
    case dates |> Enum.map(& &1.value) |> Enum.uniq() do
      [_, _ | _] = values ->
        chosen = choose.(values)
        Enum.filter(dates, &(&1.value == chosen))

      _ ->
        []
    end
  end

  defp origin_document(lines) do
    for values <- Labels.lines_below(lines, "DOC ORIGEM", 2, ["CPF", "NATURALIDADE"]),
        values != [],
        text = Enum.map_join(values, " ", & &1.text),
        [candidate] <- [Parsers.text(text)],
        do:
          Map.put(
            candidate,
            :confidence,
            Float.round(Enum.sum(Enum.map(values, & &1.confidence)) / length(values), 4)
          )
  end
end
