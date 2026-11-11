defmodule DocumentOcrWeb.DocumentInput do
  @moduledoc """
  Normalizes JSON and multipart extraction requests into document attributes and uploads.

  Only the document is required. Without `document_type` the type is `"auto"` and the
  pipeline detects it; without `country` it is `"BR"`, the only one supported; without
  `external_id` a UUID is generated. The tenant comes from the authenticated service
  account; `app_id` is used only when authentication is disabled.

  ## Examples

      {:ok, %{document_type: "auto", country: "BR"}, [%{side: "single"}]} =
        DocumentOcrWeb.DocumentInput.attributes(%{"file" => upload}, conn)
  """

  @doc """
  Builds document attributes and uploads from request parameters.

  ## Parameters
    - params: validated parameters, JSON (`images`, flat or nested `document`) or multipart
      (`file`, or `image_front` / `image_back`)
    - conn: the connection, for the company, request ID and `Idempotency-Key`

  ## Returns
    - `{:ok, attributes, uploads}`
    - `{:error, :invalid_request}` for unknown values or unreadable files
  """
  @spec attributes(map(), Plug.Conn.t()) :: {:ok, map(), [map()]} | {:error, atom()}
  def attributes(%{"document" => document} = params, conn) when is_map(document) do
    params
    |> Map.delete("document")
    |> Map.put("document_type", document["type"])
    |> Map.put("country", document["country"])
    |> attributes(conn)
  end

  def attributes(params, conn) do
    with app when is_binary(app) <- company_id(conn, params),
         {:ok, type} <- valid_type(params["document_type"]),
         {:ok, country} <- valid_country(params["country"]),
         {:ok, uploads} <- uploads(params) do
      {:ok,
       %{
         app_id: app,
         external_id: params["external_id"] || Ecto.UUID.generate(),
         requested_external_id: params["external_id"],
         document_type: type,
         country: country,
         idempotency_key: idempotency_key(conn),
         request_id: request_id(conn)
       }, uploads}
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp uploads(%{"images" => images}) when is_list(images), do: json_uploads(images)
  defp uploads(params), do: multipart_uploads(params)

  defp json_uploads(images) when length(images) in 1..2 do
    Enum.reduce_while(images, {:ok, []}, fn image, {:ok, uploads} ->
      append_json_upload(json_upload(image), uploads)
    end)
  end

  defp json_uploads(_), do: {:error, :invalid_request}

  defp append_json_upload({:ok, upload}, uploads) do
    append_unique_upload(Enum.any?(uploads, &(&1.side == upload.side)), upload, uploads)
  end

  defp append_json_upload(_, _), do: {:halt, {:error, :invalid_request}}
  defp append_unique_upload(true, _upload, _uploads), do: {:halt, {:error, :invalid_request}}
  defp append_unique_upload(false, upload, uploads), do: {:cont, {:ok, uploads ++ [upload]}}

  defp json_upload(%{"side" => side, "image" => encoded} = image)
       when side in ["front", "back", "single"] and is_binary(encoded) do
    filename = Map.get(image, "filename", side <> ".bin")
    mime_type = Map.get(image, "mime_type", "application/octet-stream")

    with true <- is_binary(filename) and byte_size(filename) > 0,
         true <- is_binary(mime_type) and byte_size(mime_type) > 0,
         {:ok, binary} when byte_size(binary) > 0 <- Base.decode64(encoded) do
      {:ok, %{side: side, binary: binary, filename: filename, mime_type: mime_type}}
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp json_upload(_), do: {:error, :invalid_request}

  defp company_id(conn, params), do: conn.assigns[:company_id] || params["app_id"]

  defp multipart_uploads(params) do
    # A single file holds the whole document (one side, or both sides on one page).
    [
      {"single", Map.get(params, "file")},
      {"front", Map.get(params, "image_front")},
      {"back", Map.get(params, "image_back")}
    ]
    |> Enum.reject(fn {_side, upload} -> is_nil(upload) end)
    |> Enum.reduce_while({:ok, []}, fn
      {side, %Plug.Upload{} = upload}, {:ok, uploads} ->
        case File.read(upload.path) do
          {:ok, binary} when byte_size(binary) > 0 ->
            value = %{
              side: side,
              binary: binary,
              filename: upload.filename,
              mime_type: upload.content_type
            }

            {:cont, {:ok, uploads ++ [value]}}

          _ ->
            {:halt, {:error, :invalid_request}}
        end

      _, _ ->
        {:halt, {:error, :invalid_request}}
    end)
    |> case do
      {:ok, []} -> {:error, :invalid_request}
      result -> result
    end
  end

  defp valid_type(nil), do: {:ok, "auto"}
  defp valid_type("cnh"), do: {:ok, "cnh"}
  defp valid_type("drivers_license"), do: {:ok, "cnh"}
  defp valid_type("rg"), do: {:ok, "rg"}
  defp valid_type("id_card"), do: {:ok, "rg"}
  defp valid_type(_), do: {:error, :invalid_request}
  defp valid_country(nil), do: {:ok, "BR"}
  defp valid_country("BR"), do: {:ok, "BR"}
  defp valid_country("BRA"), do: {:ok, "BR"}
  defp valid_country(_), do: {:error, :invalid_request}

  defp request_id(conn),
    do: List.first(Plug.Conn.get_resp_header(conn, "x-request-id")) || Ecto.UUID.generate()

  defp idempotency_key(conn), do: List.first(Plug.Conn.get_req_header(conn, "idempotency-key"))
end
