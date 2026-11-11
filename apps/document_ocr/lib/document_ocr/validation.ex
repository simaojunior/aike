defmodule DocumentOcr.Validation do
  @moduledoc """
  Validates extracted fields and decides the outcome of an extraction.

  Each field gets a rule: CPF check digits for `cpf`, a real calendar date for date fields,
  and non-empty text for the others. A field that fails its rule is `rejected`; one under
  0.90 confidence is `requires_confirmation`. Only the required fields of the document
  type decide the outcome: an optional field that is missing or doubtful does not reject
  the document.

  ## Fields
    - required for a CNH: `full_name`, `cpf`, `birth_date`
    - required for an RG: `full_name`, `rg_number`, `birth_date`
    - unknown types treat every field as required

  ## Examples

      result = DocumentOcr.Validation.validate_result(extracted)
      :completed = DocumentOcr.Validation.outcome(result)
  """
  @doc """
  Normalizes a CPF and checks its check digits.

  ## Parameters
    - value: the CPF, with or without dots, dashes or spaces

  ## Returns
    - `{:ok, digits}` with the 11 digits
    - `{:error, :invalid_cpf}` for a wrong length, repeated digits or wrong check digits

  ## Example

      {:ok, "52998224725"} = DocumentOcr.Validation.validate_cpf("529.982.247-25")
  """
  @spec validate_cpf(term()) :: {:ok, String.t()} | {:error, :invalid_cpf}
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

  @doc """
  Checks an ISO 8601 date against the calendar.

  ## Parameters
    - value: a date such as `"1990-03-12"`

  ## Returns
    - `{:ok, date}`
    - `{:error, :invalid_date}`
  """
  @spec validate_date(term()) :: {:ok, String.t()} | {:error, :invalid_date}
  def validate_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, Date.to_iso8601(date)}
      _ -> {:error, :invalid_date}
    end
  end

  def validate_date(_), do: {:error, :invalid_date}

  @required %{
    "cnh" => ~w(full_name cpf birth_date),
    "rg" => ~w(full_name rg_number birth_date)
  }

  @doc """
  The fields a document type must have.

  ## Parameters
    - type: `"cnh"` or `"rg"`

  ## Returns
    - the internal field keys; `[]` for other types
  """
  @spec required(String.t()) :: [String.t()]
  def required(type), do: Map.get(@required, type, [])

  @date_fields ~w(birth_date issue_date expiration_date first_license_date)

  @doc """
  Validates every field and sets its status and the rules applied.

  Results stored before `fields` used the `person` key; they are read as `fields`.

  ## Parameters
    - result: extraction output with `"document"` and `"fields"`

  ## Returns
    - the result with each field's `"status"` and `"validation"`
  """
  @spec validate_result(map()) :: map()
  def validate_result(%{"person" => person} = result),
    do: result |> Map.delete("person") |> Map.put("fields", person) |> validate_result()

  def validate_result(%{"fields" => fields} = result),
    do: Map.put(result, "fields", Map.new(fields, &validate_field/1))

  defp validate_field({key, field}) do
    {passed, rules} = rule(key, field["value"])

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
  end

  defp rule("cpf", value),
    do: {match?({:ok, _}, validate_cpf(value)), ["non_empty", "cpf_checksum"]}

  defp rule(key, value) when key in @date_fields,
    do: {match?({:ok, _}, validate_date(value)), ["non_empty", "valid_date"]}

  defp rule(_key, value), do: {is_binary(value) and String.trim(value) != "", ["non_empty"]}

  @doc """
  The lowest confidence among the required fields.

  ## Parameters
    - result: a validated result

  ## Returns
    - a confidence from 0 to 1; `0.0` without required fields
  """
  @spec confidence(map()) :: number()
  def confidence(result),
    do: result |> required_fields() |> Enum.map(& &1["confidence"]) |> Enum.min(fn -> 0.0 end)

  @doc """
  Decides the final state of an extraction from its required fields.

  ## Parameters
    - result: a validated result

  ## Returns
    - `:rejected` when a required field is missing or fails its rule
    - `:requires_confirmation` when a required field is under 0.90 confidence
    - `:completed` otherwise
  """
  @spec outcome(map()) :: :completed | :requires_confirmation | :rejected
  def outcome(result) do
    statuses = result |> required_fields() |> Enum.map(& &1["status"])

    cond do
      statuses == [] or "rejected" in statuses -> :rejected
      confidence(result) < 0.90 -> :requires_confirmation
      true -> :completed
    end
  end

  defp required_fields(%{"fields" => fields} = result) do
    case Map.get(@required, get_in(result, ["document", "type"])) do
      nil ->
        Map.values(fields)

      keys ->
        for key <- keys, do: Map.get(fields, key, %{"status" => "rejected", "confidence" => 0.0})
    end
  end

  defp required_fields(%{"person" => _} = result),
    do: result |> validate_result() |> required_fields()
end
