defmodule BiometricsWeb.FacematchJSON do
  @moduledoc """
  The facematch resource, in the response envelope shared by every processing API
  (`AikeHttp.Envelope`). Creation, reuse and reads return this same representation.

  ## Properties
    - `id`, `version`
    - `status`: `pending`, `processing`, `completed` or `failed`
    - `error`: `code` and `message` when the comparison failed; otherwise `null`
    - `data`: one item once both files had a usable face; empty before that, and empty when
      a file had no usable face (`filesInfo` tells which and why). The item has:
      - `faceMatch`: `matched`, `similarity` (0 to 1, two decimals) and `decision`
        (`approved`, `manual_review` or `rejected`)
      - `resources`: the face used in each file: `fieldname`, `page` and `face`
        (`confidence`, `boundingBox` as proportions of the image)
    - `metadata`: `filesInfo` (`fieldname`, `mimetype`, `size`, `sha256`, `faces` found and
      `issues`: `no_face`, `multiple_faces`, `face_too_small`), `processingTimeMs` (once
      finished), `createdAt`, `updatedAt`

  ## Examples

      %{"status" => "completed", "data" => [%{"faceMatch" => %{"matched" => true}}]} =
        session |> BiometricsWeb.FacematchJSON.data() |> Jason.encode!() |> Jason.decode!()
  """
  alias AikeHttp.Envelope

  @finished ~w(completed failed)
  @public_fields %{"selfie_image" => "selfieImage", "document_image" => "documentImage"}

  @doc """
  Builds the representation of a facematch session.

  ## Parameters
    - session: the session, with `result`, `selfie_blob` and `document_blob` preloaded

  ## Returns
    - a `Jason.OrderedObject` with camelCased keys
  """
  @spec data(Biometrics.Facematches.FacematchSession.t()) :: Jason.OrderedObject.t()
  def data(session) do
    Envelope.wrap(
      id: session.id,
      status: session.status,
      error: error(session),
      data: items(session),
      metadata:
        Envelope.object(
          files_info: [
            file_info("selfie_image", session.selfie_blob, result_data(session)),
            file_info("document_image", session.document_blob, result_data(session))
          ],
          processing_time_ms: processing_time(session),
          created_at: session.inserted_at,
          updated_at: session.updated_at
        )
    )
  end

  defp items(%{status: "completed", result: %{}, similarity_score: score} = session)
       when is_number(score) do
    [
      Envelope.object(
        face_match:
          Envelope.object(
            matched: session.matched,
            similarity: round_score(score),
            decision: session.decision
          ),
        resources: Enum.map(Map.get(session.result.data, "resources", []), &resource/1)
      )
    ]
  end

  defp items(_session), do: []

  defp resource(resource) do
    face = resource["face"] || %{}

    Envelope.object(
      fieldname: public_field(resource["fieldname"]),
      page: resource["page"],
      face:
        Envelope.object(
          confidence: round_score(face["confidence"]),
          bounding_box: bounding_box(face["bounding_box"])
        )
    )
  end

  defp bounding_box(%{} = box),
    do:
      Envelope.object(
        top: box["top"],
        left: box["left"],
        width: box["width"],
        height: box["height"]
      )

  defp bounding_box(_box), do: nil

  defp result_data(%{result: %{data: data}}) when is_map(data), do: data
  defp result_data(_session), do: %{}

  defp error(%{status: "failed"}),
    do: %{code: "processing_failed", message: "The faces could not be compared"}

  defp error(_session), do: nil

  defp public_field(field), do: Map.get(@public_fields, field, field)

  defp file_info(fieldname, blob, data) do
    stored =
      case blob do
        %AikeStorage.Blob{} ->
          [mimetype: blob.mime_type, size: blob.byte_size, sha256: blob.sha256]

        _ ->
          []
      end

    Envelope.object(
      [fieldname: public_field(fieldname)] ++
        stored ++
        [faces: get_in(data, ["faces", fieldname]), issues: get_in(data, ["issues", fieldname])]
    )
  end

  defp round_score(score) when is_number(score), do: Float.round(score / 1, 2)
  defp round_score(score), do: score

  defp processing_time(%{status: status, inserted_at: started, updated_at: finished})
       when status in @finished and not is_nil(started) and not is_nil(finished),
       do: DateTime.diff(finished, started, :millisecond)

  defp processing_time(_session), do: nil
end
