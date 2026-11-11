defmodule DocumentOcr.Extraction.Layout do
  @moduledoc """
  Geometry of OCR lines for label extraction.

  Labels are found token by token across the words of a line, so labels printed side by
  side ("VALIDADE 1º HABILITAÇÃO") keep their own columns. A value is the run of words that
  starts inside its label's column and continues while the gaps between words stay small,
  so long values such as names may extend past the label. Labels of five or more letters
  tolerate one OCR slip ("NATURALIDAD"). Lines from engines without word boxes are split
  into words with boxes proportional to their position in the text.

  Sources: the Tesseract engine names each line's source `"<image>.<pass>"` (after the
  pipeline merges uploads, `"<upload>:<image>.<pass>"`). Every pass of one image shares
  its coordinates, so a label found in one pass can locate values in the others. Sources
  without a pass (older results, other engines) are their own image.

  ## Examples

      [label | _] = DocumentOcr.Extraction.Layout.find(lines, "DATA NASCIMENTO")
      [%{text: "12/03/1990"}] = DocumentOcr.Extraction.Layout.column_below(lines, label, 1)
  """

  @max_gap_heights 4
  @column_slack_heights 1.5
  @word_gap_heights 2.5

  @doc """
  Finds every occurrence of a label.

  ## Parameters
    - lines: prepared lines, with words
    - label: the label words

  ## Returns
    - one map per occurrence: `:line`, `:source`, `:box` (the label's words) and `:last`
      (index of its last word)
  """
  @spec find([map()], String.t()) :: [map()]
  def find(lines, label) do
    tokens = tokens(label)

    for line <- lines,
        {first, last} <- matches(line["words"], tokens) do
      words = Enum.slice(line["words"], first..last)
      %{line: line, source: line["source"], box: union(Enum.map(words, & &1["bbox"])), last: last}
    end
  end

  defp matches(words, tokens) do
    flat =
      for {word, index} <- Enum.with_index(words),
          token <- String.split(normalize(word["text"])),
          do: {token, index}

    size = length(tokens)

    for first <- 0..(length(flat) - size)//1,
        window = Enum.slice(flat, first, size),
        Enum.zip(window, tokens)
        |> Enum.all?(fn {{word, _}, token} -> same_token?(word, token) end),
        do: {window |> hd() |> elem(1), window |> List.last() |> elem(1)}
  end

  @doc """
  The same label occurrence placed in every OCR pass of its image.

  ## Parameters
    - lines: prepared lines
    - found: a label occurrence from `find/2`

  ## Returns
    - one occurrence per pass of the image, with `:source` set to that pass
  """
  @spec passes([map()], map()) :: [map()]
  def passes(lines, %{source: source} = found) do
    image = image(source)

    lines
    |> Enum.map(& &1["source"])
    |> Enum.uniq()
    |> Enum.filter(&(image(&1) == image))
    |> Enum.map(&%{found | source: &1})
  end

  @doc """
  Keeps the first occurrence of a label in each image, so passes that all read the label
  do not count each value once per pass.

  ## Parameters
    - found: occurrences from `find/2`

  ## Returns
    - at most one occurrence per image
  """
  @spec one_per_image([map()]) :: [map()]
  def one_per_image(found), do: Enum.uniq_by(found, &image(&1.source))

  defp image(source) when is_binary(source) do
    case Regex.run(~r/\A(.+)\.[^.]+\z/, source) do
      [_, image] -> image
      nil -> source
    end
  end

  defp image(source), do: source

  @doc """
  Tells whether a whole line is a label read with one slip, such as "CCPF" for "CPF".

  ## Parameters
    - text: the line text
    - label: the label words

  ## Returns
    - `true` when the line, without spaces, is at most one letter longer than the label
      and close to it (Jaro similarity of at least 0.9)
  """
  @spec misread_label?(String.t(), String.t()) :: boolean()
  def misread_label?(text, label) do
    line = text |> normalize() |> String.replace(" ", "")
    target = label |> normalize() |> String.replace(" ", "")

    abs(String.length(line) - String.length(target)) <= 1 and
      String.jaro_distance(line, target) >= 0.9
  end

  @doc """
  Tells whether a text contains a label.

  ## Parameters
    - text: any text
    - label: the label words

  ## Returns
    - `true` when the label words appear in order
  """
  @spec label_text?(String.t(), String.t()) :: boolean()
  def label_text?(text, label) do
    words = text |> String.split() |> Enum.map(&%{"text" => &1})
    matches(words, tokens(label)) != []
  end

  defp same_token?(word, token) when byte_size(token) >= 5,
    do: word == token or String.jaro_distance(word, token) >= 0.9

  defp same_token?(word, token), do: word == token

  defp tokens(label), do: label |> String.split() |> Enum.map(&normalize/1)

  @doc """
  Values in the label's column on the lines below it.

  ## Parameters
    - lines: prepared lines, with words
    - found: a label occurrence from `find/2`
    - count: the most lines to read

  ## Returns
    - up to `count` values, top to bottom; each with `:text`, `:confidence` and `:top`
  """
  @spec column_below([map()], map(), pos_integer()) :: [map()]
  def column_below(lines, %{source: source, box: [left, top, width, height]}, count) do
    lines
    |> Enum.filter(fn %{"source" => line_source, "bbox" => [_, line_top, _, line_height]} ->
      center = line_top + line_height / 2

      line_source == source and center > top + height and
        center <= top + height * @max_gap_heights * count
    end)
    |> Enum.sort_by(fn %{"bbox" => [_, line_top, _, _]} -> line_top end)
    |> Enum.map(&column_words(&1, left, left + width, height))
    |> Enum.reject(&(&1 == nil))
    |> Enum.take(count)
  end

  defp column_words(line, left, right, height) do
    slack = height * @column_slack_heights

    run =
      line["words"]
      |> Enum.drop_while(fn %{"bbox" => [word_left, _, _, _]} ->
        word_left < left - slack or word_left > right + slack
      end)
      |> contiguous(height * @word_gap_heights)

    value(run)
  end

  defp value([]), do: nil

  defp value(run) do
    %{
      text: Enum.map_join(run, " ", & &1["text"]),
      confidence: mean_confidence(run),
      top: run |> Enum.map(fn %{"bbox" => [_, word_top, _, _]} -> word_top end) |> Enum.min()
    }
  end

  defp contiguous([], _gap), do: []

  defp contiguous([first | rest], gap) do
    {run, _} =
      Enum.reduce_while(rest, {[first], first}, fn word, {run, previous} ->
        [previous_left, _, previous_width, _] = previous["bbox"]
        [word_left, _, _, _] = word["bbox"]
        next_word(word_left - (previous_left + previous_width), gap, word, run, previous)
      end)

    run
  end

  defp next_word(distance, gap, word, run, _previous) when distance <= gap,
    do: {:cont, {run ++ [word], word}}

  defp next_word(_distance, _gap, _word, run, previous), do: {:halt, {run, previous}}

  @doc """
  Average confidence of words, rounded to four decimals.

  ## Parameters
    - words: words with `"confidence"` from 0 to 1

  ## Returns
    - the average confidence
  """
  @spec mean_confidence([map()]) :: float()
  def mean_confidence(words),
    do: Float.round(Enum.sum(Enum.map(words, & &1["confidence"])) / length(words), 4)

  defp union(boxes) do
    left = boxes |> Enum.map(&Enum.at(&1, 0)) |> Enum.min()
    top = boxes |> Enum.map(&Enum.at(&1, 1)) |> Enum.min()
    right = boxes |> Enum.map(fn [l, _, w, _] -> l + w end) |> Enum.max()
    bottom = boxes |> Enum.map(fn [_, t, _, h] -> t + h end) |> Enum.max()
    [left, top, right - left, bottom - top]
  end

  @doc """
  Gives a line its words. Lines that already have words are kept.

  ## Parameters
    - line: an OCR line

  ## Returns
    - the line with `"words"`
  """
  @spec with_words(map()) :: map()
  def with_words(%{"words" => [_ | _]} = line), do: line

  def with_words(%{"text" => text, "bbox" => [left, top, width, height]} = line) do
    char_width = width / max(String.length(text), 1)

    words =
      for [{offset, length}] <- Regex.scan(~r/\S+/u, text, return: :index) do
        %{
          "text" => binary_part(text, offset, length),
          "confidence" => line["confidence"],
          "bbox" => [left + offset * char_width, top, length * char_width, height]
        }
      end

    Map.put(line, "words", words)
  end

  @doc """
  Tells whether a value is a well-formed OCR line.

  ## Parameters
    - line: any value

  ## Returns
    - `true` for a line with text, confidence from 0 to 1, a box, a source and valid words
  """
  @spec line?(term()) :: boolean()
  def line?(%{"text" => text, "confidence" => confidence, "bbox" => [_, _, _, _] = bbox} = line)
      when is_binary(text) and is_number(confidence) and confidence >= 0 and confidence <= 1 do
    Map.has_key?(line, "source") and Enum.all?(bbox, &is_number/1) and
      words?(Map.get(line, "words", []))
  end

  def line?(_), do: false

  defp words?(words) when is_list(words) do
    Enum.all?(words, fn
      %{"text" => text, "confidence" => confidence, "bbox" => [_, _, _, _] = bbox}
      when is_binary(text) and is_number(confidence) ->
        Enum.all?(bbox, &is_number/1)

      _ ->
        false
    end)
  end

  defp words?(_), do: false

  defp normalize(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9\s]/, " ")
    |> String.split()
    |> Enum.join(" ")
  end
end
