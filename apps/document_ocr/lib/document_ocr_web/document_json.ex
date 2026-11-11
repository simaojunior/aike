defmodule DocumentOcrWeb.DocumentJSON do
  @moduledoc """
  The extraction resource, in the response envelope shared by every processing API
  (`AikeHttp.Envelope`). Every extraction endpoint returns this same representation.

  ## Properties
    - `id`, `version`, `runId`
    - `status`: `pending`, `processing`, `completed`, `requires_confirmation`, `rejected`,
      `failed` or `cancelled`
    - `error`: `code` and `message`, only when the extraction failed; otherwise `null`
    - `data`: empty until a result exists; then one item with:
      - `classification`: `type` (`drivers_license`, `id_card`), `subtype` (`printed`,
        `digital`), `country` (`BRA`) and `side` (`only_front`, `only_back`,
        `front_and_back`, `unknown`)
      - `person` and `document`: one entry per field read, each with `confidence` (0 to 1,
        two decimals), `rawValue`, `status` and `value`. Required fields are always present
        (`value: null`, `status: rejected` when not read); the others only when the
        document shows them
    - `metadata`: `filesInfo` (`side`, `mimetype`, `size`, `sha256` per image),
      `processingTimeMs` (once the extraction finished), `createdAt`, `updatedAt`

  Results stored before `fields` used the `person` key; both are read.

  ## Examples

      %{"status" => "completed", "data" => [%{"classification" => %{"type" => "id_card"}}]} =
        document |> DocumentOcrWeb.DocumentJSON.data() |> Jason.encode!() |> Jason.decode!()
  """
  alias AikeHttp.Envelope
  alias KycCore.{Country, DocumentSide, DocumentType}

  @finished ~w(completed requires_confirmation rejected failed cancelled)
  @public_field_keys ~w(confidence raw_value status value)

  @person [
    {"full_name", :name},
    {"cpf", :tax_id},
    {"birth_date", :birthdate},
    {"mothers_name", :mothers_name},
    {"fathers_name", :fathers_name},
    {"birthplace", :birthplace}
  ]

  @document [
    {"rg_number", :number},
    {"registration_number", :registration_number},
    {"category", :category},
    {"expiration_date", :expiration_date},
    {"first_license_date", :first_license_date},
    {"issue_date", :issue_date},
    {"issue_place", :issue_place},
    {"identity_number", :identity_number},
    {"identity_issuer", :identity_issuer},
    {"identity_state", :identity_state},
    {"origin_document", :origin_document}
  ]

  @doc """
  Builds the representation of an extraction.

  ## Parameters
    - document: the document, with `images: :blob` and `result` preloaded

  ## Returns
    - a `Jason.OrderedObject` with camelCased keys
  """
  @spec data(map()) :: Jason.OrderedObject.t()
  def data(document) do
    Envelope.wrap(
      id: document.id,
      status: document.status,
      run_id: document.run_id,
      error: error(document),
      data: items(document, result(document)),
      metadata: %{
        files_info: files_info(document),
        processing_time_ms: processing_time(document),
        created_at: document.inserted_at,
        updated_at: document.updated_at
      }
    )
  end

  defp result(%{result: %{run_id: run_id, data: data}, run_id: run_id}), do: data
  defp result(_document), do: nil

  defp items(_document, nil), do: []

  defp items(document, result) do
    described = Map.get(result, "document", %{})
    type = Map.get(described, "type", document.document_type)
    fields = fields(result)

    [
      Envelope.object(
        classification:
          Envelope.object(
            type: DocumentType.public(type),
            subtype: Map.get(described, "subtype", "printed"),
            country: Country.alpha3(Map.get(described, "country", document.country)),
            side: DocumentSide.public(Map.get(described, "side", "unknown"))
          ),
        person: group(fields, @person, type),
        document: group(fields, @document, type)
      )
    ]
  end

  defp fields(%{"fields" => fields}), do: fields
  defp fields(%{"person" => fields}), do: fields
  defp fields(_result), do: %{}

  defp group(fields, names, type) do
    required = DocumentOcr.Validation.required(type)

    for {key, name} <- names, Map.has_key?(fields, key) or key in required do
      {name, public_field(fields[key])}
    end
    |> Envelope.object()
  end

  defp public_field(nil), do: public_field(%{"confidence" => 0.0, "status" => "rejected"})

  defp public_field(field) do
    field
    |> Map.update("confidence", nil, &round_confidence/1)
    |> then(fn field -> Enum.map(@public_field_keys, &{&1, Map.get(field, &1)}) end)
    |> Envelope.object()
  end

  defp round_confidence(confidence) when is_number(confidence),
    do: Float.round(confidence / 1, 2)

  defp round_confidence(confidence), do: confidence

  defp error(%{status: "failed", error_code: code, error_message: message}),
    do: %{code: code, message: message}

  defp error(_document), do: nil

  defp files_info(%{images: images}) when is_list(images) do
    images
    |> Enum.sort_by(&side_order(&1.side))
    |> Enum.map(&file_info/1)
  end

  defp files_info(_document), do: []

  defp file_info(%{side: side, blob: %AikeStorage.Blob{} = blob}),
    do: %{side: side, mimetype: blob.mime_type, size: blob.byte_size, sha256: blob.sha256}

  defp file_info(%{side: side}), do: %{side: side}

  defp side_order("front"), do: 0
  defp side_order("single"), do: 1
  defp side_order(_), do: 2

  defp processing_time(%{status: status, inserted_at: started, updated_at: finished})
       when status in @finished and not is_nil(started) and not is_nil(finished),
       do: DateTime.diff(finished, started, :millisecond)

  defp processing_time(_document), do: nil
end
