defmodule DocumentOcr.Extraction.Labels do
  @moduledoc """
  Reads document fields from OCR lines by their printed labels.

  The public interface of label extraction: find a label, read the value printed below it
  or to its right, and choose the best value among all OCR passes. Geometry lives in
  `DocumentOcr.Extraction.Layout` and value parsing in `DocumentOcr.Extraction.Parsers`.
  Geometry is compared only inside one OCR pass ("source"). Across passes, the value that
  passes validation, repeats most and has the highest confidence wins.

  ## Examples

      {:ok, lines} = DocumentOcr.Extraction.Labels.prepare(raw_ocr)
      candidates = DocumentOcr.Extraction.Labels.below(lines, "NOME", &Parsers.name/1)
      %{"value" => "NARUTO UZUMAKI"} = DocumentOcr.Extraction.Labels.best(candidates)
  """
  alias DocumentOcr.Extraction.{Layout, Parsers}

  @type candidate :: Parsers.candidate()
  @type parser :: Parsers.parser()

  @doc """
  Checks the OCR output and gives every line its words.

  ## Parameters
    - raw: OCR engine output, `%{"text" => lines}`; each line has `text`, `confidence`
      (0 to 1), `bbox` (`[left, top, width, height]`), `source` and, optionally, `words`

  ## Returns
    - `{:ok, lines}` ready for the other functions
    - `{:error, :invalid_ocr_output}` when the output is empty or malformed
  """
  @spec prepare(term()) :: {:ok, [map()]} | {:error, :invalid_ocr_output}
  def prepare(%{"text" => [_ | _] = lines}),
    do: prepared(Enum.all?(lines, &Layout.line?/1), lines)

  def prepare(_), do: {:error, :invalid_ocr_output}

  defp prepared(true, lines), do: {:ok, Enum.map(lines, &Layout.with_words/1)}
  defp prepared(false, _lines), do: {:error, :invalid_ocr_output}

  @doc """
  Values printed on the nearest line below each `label`, inside the label's column.

  A label found in one OCR pass also locates the value in the other passes of the same
  image (`Layout.passes/2`): a faint label may be read only with stretched contrast,
  while its value reads best in plain grayscale. The votes of `best/1` then choose.

  ## Parameters
    - lines: lines from `prepare/1`
    - label: the label words, such as `"DATA NASCIMENTO"`
    - parse: a parser from `DocumentOcr.Extraction.Parsers`

  ## Returns
    - the candidates found under every occurrence of the label, in all passes

  ## Example

      Labels.below(lines, "CPF", &Parsers.cpf/1)
  """
  @spec below([map()], String.t(), parser()) :: [candidate()]
  def below(lines, label, parse) do
    for found <- lines |> Layout.find(label) |> Layout.one_per_image(),
        pass <- Layout.passes(lines, found),
        [value | _] <- [Layout.column_below(lines, pass, 1)],
        candidate <- parse.(value.text),
        do: Map.put(candidate, :confidence, value.confidence)
  end

  @doc """
  Texts of up to `count` lines below each `label`, stopping at the next label.

  ## Parameters
    - lines: lines from `prepare/1`
    - label: the label words, such as `"FILIACAO"`
    - count: the most lines to read
    - stop_labels: labels that end the value

  ## Returns
    - one list per label found; each value has `:text`, `:confidence`, `:top` and `:gap`
      (its distance below the label, in label heights)
  """
  @spec lines_below([map()], String.t(), pos_integer(), [String.t()]) :: [[map()]]
  def lines_below(lines, label, count, stop_labels) do
    for found <- lines |> Layout.find(label) |> Layout.one_per_image(),
        %{box: [_, top, _, height]} = pass <- Layout.passes(lines, found) do
      lines
      |> Layout.column_below(pass, count)
      |> Enum.take_while(fn value ->
        not Enum.any?(
          stop_labels,
          &(Layout.label_text?(value.text, &1) or Layout.misread_label?(value.text, &1))
        )
      end)
      |> Enum.map(&Map.put(&1, :gap, (&1.top - (top + height)) / height))
    end
  end

  @doc """
  Values printed on the same line, right after each `label`.

  ## Parameters
    - lines: lines from `prepare/1`
    - label: the label words, such as `"REGISTRO GERAL"`
    - parse: a parser from `DocumentOcr.Extraction.Parsers`

  ## Returns
    - the candidates found after every occurrence of the label
  """
  @spec right_of([map()], String.t(), parser()) :: [candidate()]
  def right_of(lines, label, parse) do
    for found <- Layout.find(lines, label),
        words = Enum.drop(found.line["words"], found.last + 1),
        words != [],
        candidate <- parse.(Enum.map_join(words, " ", & &1["text"])),
        do: Map.put(candidate, :confidence, Layout.mean_confidence(words))
  end

  @doc """
  Values found on any line, with no label.

  ## Parameters
    - lines: lines from `prepare/1`
    - parse: a parser from `DocumentOcr.Extraction.Parsers`

  ## Returns
    - the candidates found in every line
  """
  @spec anywhere([map()], parser()) :: [candidate()]
  def anywhere(lines, parse) do
    for line <- lines,
        candidate <- parse.(line["text"]),
        do: Map.put(candidate, :confidence, line["confidence"])
  end

  @doc """
  Chooses one value among the candidates of a field.

  The value that passes validation wins; then the one read by most passes; then the one
  with the highest confidence. Without candidates, the field is missing: validation
  rejects it instead of failing the extraction.

  ## Parameters
    - candidates: candidates from `below/3`, `right_of/3` or `anywhere/2`

  ## Returns
    - `%{"value", "raw_value", "confidence", "status"}`
  """
  @spec best([candidate()]) :: map()
  def best([]),
    do: %{"value" => nil, "raw_value" => nil, "confidence" => 0.0, "status" => "rejected"}

  def best(candidates) do
    {candidate, _} =
      candidates
      |> Enum.group_by(& &1.value)
      |> Enum.map(fn {_, group} -> {Enum.max_by(group, & &1.confidence), length(group)} end)
      |> Enum.max_by(fn {candidate, votes} -> {candidate.valid, votes, candidate.confidence} end)

    %{
      "value" => candidate.value,
      "raw_value" => candidate.raw_value,
      "confidence" => candidate.confidence,
      "status" => "accepted"
    }
  end

  @doc """
  Adds an optional field only when it was read. Optional fields are absent, never empty.

  ## Parameters
    - fields: the fields extracted so far
    - key: the field name, such as `"mothers_name"`
    - candidates: the candidates of that field

  ## Returns
    - `fields`, with `key` added when there are candidates
  """
  @spec put_found(map(), String.t(), [candidate()]) :: map()
  def put_found(fields, _key, []), do: fields
  def put_found(fields, key, candidates), do: Map.put(fields, key, best(candidates))
end
