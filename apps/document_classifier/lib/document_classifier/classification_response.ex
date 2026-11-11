defmodule DocumentClassifier.ClassificationResponse do
  @moduledoc """
  Builds the classification response in the envelope shared by every processing API
  (`AikeHttp.Envelope`), for multipart uploads and JSON (base64) requests alike.

  ## Properties
    - `id`, `version`
    - `data`: one item when a document type was recognized, otherwise empty:
      - `classification`: `type` (`drivers_license`, `id_card`), `subtype` (`printed`,
        `digital`, only when the engine reports it), `country` (`BRA`), `side`
        (`only_front`, `only_back`, `front_and_back`, `unknown`) and `confidence`
      - `quality`: `isAccepted` and `issues`
      - `fileInfo`: the `fieldname` of the file
    - `metadata`: `filesInfo` (`fieldname`, `name`, `size`, `mimetype`, `sha256`) and
      `processingTimeMs`

  ## Examples

      DocumentClassifier.ClassificationResponse.build(result, {:image, encoded}, started_at)
  """
  alias AikeHttp.Envelope
  alias KycCore.{Country, DocumentSide, DocumentType}

  @type source :: Plug.Upload.t() | {:image, String.t()}

  @doc """
  Builds the response body.

  ## Parameters
    - result: the engine result (`document`, `confidence`, `quality`)
    - source: the uploaded file, or `{:image, base64}` for a JSON request
    - started_at: `System.monotonic_time(:millisecond)` when the work started

  ## Returns
    - a `Jason.OrderedObject` ready to render
  """
  @spec build(map(), source(), integer()) :: Jason.OrderedObject.t()
  def build(result, source, started_at) do
    file = file_info(source)

    Envelope.wrap(
      id: DocumentClassifier.Identifier.generate(),
      data: data(result, file),
      metadata:
        Envelope.object(
          files_info: [file],
          processing_time_ms: System.monotonic_time(:millisecond) - started_at
        )
    )
  end

  defp data(%{"document" => %{"type" => type}} = result, file) when type in ["cnh", "rg"] do
    [
      Envelope.object(
        classification: classification(result),
        quality:
          Envelope.object(
            is_accepted: result["quality"]["acceptable"],
            issues: result["quality"]["issues"]
          ),
        file_info: Envelope.object(fieldname: file["fieldname"])
      )
    ]
  end

  defp data(_result, _file), do: []

  defp classification(%{"document" => document} = result) do
    [
      type: DocumentType.public(document["type"]),
      subtype: document["subtype"],
      country: Country.alpha3(document["country"]),
      side: DocumentSide.public(document["side"]),
      confidence: result["confidence"]
    ]
    |> Enum.reject(&match?({:subtype, nil}, &1))
    |> Envelope.object()
  end

  defp file_info(%Plug.Upload{} = upload) do
    upload.path |> File.read!() |> file_info("file", upload.filename, upload.content_type)
  end

  defp file_info({:image, encoded}) do
    bytes = Base.decode64!(encoded)
    file_info(bytes, "image", nil, mimetype(bytes))
  end

  defp mimetype(<<0xFF, 0xD8, _::binary>>), do: "image/jpeg"
  defp mimetype(<<0x89, "PNG", _::binary>>), do: "image/png"
  defp mimetype(<<"%PDF", _::binary>>), do: "application/pdf"
  defp mimetype(_bytes), do: nil

  defp file_info(bytes, fieldname, name, mimetype) do
    Envelope.object(
      fieldname: fieldname,
      name: name,
      size: byte_size(bytes),
      mimetype: mimetype,
      sha256: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    )
  end
end
