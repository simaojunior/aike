defmodule DocumentOcr.Extraction.Filiation do
  @moduledoc """
  Reads the parents printed below the "FILIAÇÃO" label.

  Brazilian documents print the father first and the mother below him, each on a fixed
  line of the box. With two names, the first is the father and the last the mother. With
  one name, its distance from the label decides: the father's line sits right below the
  label (at most two label heights), the mother's further down.

  ## Examples

      %{"mothers_name" => %{"value" => "KUSHINA UZUMAKI"}} =
        DocumentOcr.Extraction.Filiation.put(lines, %{})
  """
  alias DocumentOcr.Extraction.{Labels, Parsers}

  @stop_labels ["PERMISSAO", "NATURALIDADE", "DOC ORIGEM", "CPF", "DATA NASCIMENTO", "ACC"]
  @father_max_gap_heights 2

  @doc """
  Adds `fathers_name` and `mothers_name` to `fields` when the document prints them.

  ## Parameters
    - lines: lines from `DocumentOcr.Extraction.Labels.prepare/1`
    - fields: the fields extracted so far

  ## Returns
    - `fields`, with the parents found
  """
  @spec put([map()], map()) :: map()
  def put(lines, fields) do
    {fathers, mothers} =
      lines
      |> Labels.lines_below("FILIACAO", 4, @stop_labels)
      |> Enum.map(&parents/1)
      |> Enum.reduce({[], []}, fn {father, mother}, {fathers, mothers} ->
        {fathers ++ father, mothers ++ mother}
      end)

    fields
    |> Labels.put_found("fathers_name", fathers)
    |> Labels.put_found("mothers_name", mothers)
  end

  defp parents(values) do
    names = for value <- values, [name] <- [Parsers.name(value.text)], do: {value, name}

    case names do
      [] -> {[], []}
      [{value, name}] -> single(value, candidate(name, value))
      [{first, father} | rest] -> two(first, father, List.last(rest))
    end
  end

  defp two(first, father, {last, mother}),
    do: {[candidate(father, first)], [candidate(mother, last)]}

  defp single(%{gap: gap}, candidate) when gap <= @father_max_gap_heights, do: {[candidate], []}
  defp single(_value, candidate), do: {[], [candidate]}

  defp candidate(name, value), do: Map.put(name, :confidence, value.confidence)
end
