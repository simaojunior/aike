defmodule DocumentOcrWeb.DocumentJSON do
  @moduledoc "JSON representations for OCR document resources."

  @spec data(map()) :: map()
  def data(document) do
    %{
      id: document.id,
      run_id: document.run_id,
      status: document.status,
      decision: document.decision,
      document_type: document.document_type,
      data: data_items(document),
      metadata: %{processing_time_ms: nil},
      result: result(document)
    }
  end

  @spec accepted(map()) :: map()
  def accepted(document), do: %{id: document.id, run_id: document.run_id, status: document.status}

  defp result(%{result: %{run_id: run_id, data: data}, run_id: run_id}), do: data
  defp result(_document), do: nil

  defp data_items(document) do
    case result(document) do
      nil -> []
      result -> [canonical_item(document, result)]
    end
  end

  defp canonical_item(document, result) do
    person = Map.get(result, "person", %{})

    %{
      classification: %{
        type: document.document_type,
        subtype: "printed",
        country: country(document.country),
        side: "front_and_back"
      },
      raw: %{person: raw_person(person)},
      normalized: %{person: normalized_person(person)},
      tax_data: tax_data(person),
      matches: %{}
    }
  end

  defp raw_person(person),
    do: %{
      "tax_id" => field_value(person, "cpf", "raw_value"),
      "name" => field_value(person, "full_name", "raw_value"),
      "birthdate" => field_value(person, "birth_date", "raw_value")
    }

  defp normalized_person(person),
    do: %{
      "tax_id" => field_value(person, "cpf", "value"),
      "name" => field_value(person, "full_name", "value"),
      "birthdate" => field_value(person, "birth_date", "value")
    }

  defp tax_data(person), do: normalized_person(person)
  defp field_value(person, key, field), do: get_in(person, [key, field])
  defp country("BR"), do: "BRA"
  defp country(country), do: country
end
