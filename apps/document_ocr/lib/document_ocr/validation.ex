defmodule DocumentOcr.Validation do
  def validate_cpf(value) when is_binary(value) do
    normalized = String.replace(value, ~r/[.\-\s]/, "")

    if Regex.match?(~r/^\d{11}$/, normalized) do
      digits = for <<digit <- normalized>>, do: digit - ?0

      if length(Enum.uniq(digits)) > 1 and
           checksum(Enum.take(digits, 9)) == Enum.at(digits, 9) and
           checksum(Enum.take(digits, 10)) == Enum.at(digits, 10),
         do: {:ok, normalized},
         else: {:error, :invalid_cpf}
    else
      {:error, :invalid_cpf}
    end
  end

  def validate_cpf(_), do: {:error, :invalid_cpf}

  defp checksum(digits) do
    sum =
      digits
      |> Enum.zip((length(digits) + 1)..2//-1)
      |> Enum.reduce(0, fn {d, w}, acc -> acc + d * w end)

    remainder = rem(sum * 10, 11)
    if remainder == 10, do: 0, else: remainder
  end

  def validate_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, Date.to_iso8601(date)}
      _ -> {:error, :invalid_date}
    end
  end

  def validate_date(_), do: {:error, :invalid_date}

  def validate_result(%{"person" => person} = result) do
    validated =
      Map.new(person, fn {key, field} ->
        {passed, rules} =
          case key do
            "cpf" ->
              {match?({:ok, _}, validate_cpf(field["value"])), ["non_empty", "cpf_checksum"]}

            "birth_date" ->
              {match?({:ok, _}, validate_date(field["value"])), ["non_empty", "valid_date"]}

            _ ->
              {is_binary(field["value"]) and String.trim(field["value"]) != "", ["non_empty"]}
          end

        status =
          cond do
            not passed -> "rejected"
            field["confidence"] < 0.90 -> "requires_confirmation"
            true -> "accepted"
          end

        {key,
         Map.merge(field, %{
           "status" => status,
           "validation" => %{"passed" => passed, "rules" => rules}
         })}
      end)

    Map.put(result, "person", validated)
  end

  def confidence(result),
    do: result["person"] |> Map.values() |> Enum.map(& &1["confidence"]) |> Enum.min()

  def outcome(result) do
    statuses = result["person"] |> Map.values() |> Enum.map(& &1["status"])

    cond do
      "rejected" in statuses -> :rejected
      confidence(result) < 0.90 -> :requires_confirmation
      true -> :completed
    end
  end
end
