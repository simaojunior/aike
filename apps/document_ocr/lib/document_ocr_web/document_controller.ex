defmodule DocumentOcrWeb.DocumentController do
  use DocumentOcrWeb, :controller
  alias DocumentOcr.Documents
  alias KycCore.JsonKeyFormatter
  alias DocumentOcrWeb.DocumentJSON

  plug(DocumentOcrWeb.ValidateParams,
    create: &DocumentOcrWeb.Schemas.DocumentParams.create/1,
    reprocess: &DocumentOcrWeb.Schemas.DocumentParams.reprocess/1
  )

  def create(conn, params) do
    with {:ok, attrs, uploads} <- attributes(params, conn),
         {:ok, %{document: document}} <- create_document(attrs, uploads) do
      conn
      |> put_status(202)
      |> json(JsonKeyFormatter.format(DocumentJSON.accepted(document)))
    else
      {:error, :invalid_processing_configuration} ->
        conn |> put_status(503) |> json(%{error: "service_unavailable"})

      _ ->
        conn |> put_status(422) |> json(%{error: "invalid_request"})
    end
  end

  defp create_document(attrs, []), do: Documents.create_document(attrs)
  defp create_document(attrs, uploads), do: Documents.create_document_from_uploads(attrs, uploads)

  def reprocess(conn, %{"id" => id, "pipeline_version" => version}) do
    request_id =
      List.first(Plug.Conn.get_resp_header(conn, "x-request-id")) || Ecto.UUID.generate()

    case Documents.reprocess_document(id, version, request_id) do
      {:ok, document} ->
        conn
        |> put_status(202)
        |> json(JsonKeyFormatter.format(DocumentJSON.accepted(document)))

      {:error, :document_not_found} ->
        not_found(conn)

      {:error, reason}
      when reason in [:invalid_pipeline_version, :unsupported_pipeline_version] ->
        conn |> put_status(422) |> json(%{error: "invalid_pipeline_version"})

      {:error, _} ->
        conn |> put_status(503) |> json(%{error: "service_unavailable"})
    end
  end

  def reprocess(conn, _), do: conn |> put_status(422) |> json(%{error: "invalid_request"})

  def cancel(conn, %{"id" => id}) do
    case Documents.cancel_document(id) do
      {:ok, document} ->
        json(
          conn,
          JsonKeyFormatter.format(
            DocumentJSON.accepted(document)
            |> Map.put(:error_code, document.error_code)
          )
        )

      {:error, :document_not_found} ->
        not_found(conn)

      {:error, :not_cancellable} ->
        conn |> put_status(409) |> json(%{error: "document_not_cancellable"})

      {:error, _} ->
        conn |> put_status(503) |> json(%{error: "service_unavailable"})
    end
  end

  def cancel(conn, _), do: conn |> put_status(422) |> json(%{error: "invalid_request"})

  def show(conn, %{"id" => id}) do
    case Documents.get_document(id) do
      nil ->
        not_found(conn)

      doc ->
        json(conn, JsonKeyFormatter.format(DocumentJSON.data(doc)))
    end
  end

  defp not_found(conn), do: conn |> put_status(404) |> json(%{error: "not_found"})

  defp attributes(
         %{
           "external_id" => external,
           "document_type" => type,
           "country" => country,
           "images" => images
         } = params,
         conn
       )
       when is_list(images) do
    app = company_id(conn, params)

    with {:ok, type} <- valid_type(type),
         {:ok, country} <- valid_country(country),
         true <- is_binary(app),
         {:ok, images} <- json_images(images) do
      {:ok,
       %{
         app_id: app,
         external_id: external,
         document_type: type,
         country: country,
         images: images,
         idempotency_key: idempotency_key(conn),
         request_id: request_id(conn)
       }, []}
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp attributes(
         %{
           "external_id" => external,
           "document" => %{"type" => type, "country" => country},
           "images" => images
         } = params,
         conn
       )
       when is_list(images) do
    images = json_images!(images)
    app = company_id(conn, params)

    if :invalid in images or type != "cnh" or is_nil(app) do
      {:error, :invalid_request}
    else
      {:ok,
       %{
         app_id: app,
         external_id: external,
         document_type: type,
         country: country,
         images: images,
         idempotency_key: idempotency_key(conn),
         request_id:
           List.first(Plug.Conn.get_resp_header(conn, "x-request-id")) || Ecto.UUID.generate()
       }, []}
    end
  end

  defp attributes(
         %{
           "external_id" => external,
           "document_type" => type,
           "country" => country
         } = params,
         conn
       ) do
    with app when is_binary(app) <- company_id(conn, params),
         {:ok, type} <- valid_type(type),
         {:ok, country} <- valid_country(country),
         {:ok, uploads} <- multipart_uploads(params) do
      {:ok,
       %{
         app_id: app,
         external_id: external,
         document_type: type,
         country: country,
         idempotency_key: idempotency_key(conn),
         request_id: request_id(conn)
       }, uploads}
    end
  end

  defp attributes(_, _), do: {:error, :invalid_request}

  defp json_images(images) do
    result = json_images!(images)
    if :invalid in result, do: {:error, :invalid_request}, else: {:ok, result}
  end

  defp json_images!(images),
    do:
      Enum.map(images, fn
        %{"side" => side, "source" => %{"type" => "object_storage", "key" => key}} ->
          %{side: side, source_key: key}

        _ ->
          :invalid
      end)

  defp company_id(conn, params), do: conn.assigns[:company_id] || params["app_id"]

  defp multipart_uploads(params) do
    uploads =
      [{"front", Map.get(params, "image_front")}, {"back", Map.get(params, "image_back")}]
      |> Enum.filter(fn {_side, upload} -> match?(%Plug.Upload{}, upload) end)
      |> Enum.map(fn {side, %Plug.Upload{} = upload} ->
        {:ok, binary} = File.read(upload.path)
        %{side: side, binary: binary, filename: upload.filename, mime_type: upload.content_type}
      end)

    if uploads == [], do: {:error, :invalid_request}, else: {:ok, uploads}
  end

  defp valid_type("cnh"), do: {:ok, "cnh"}
  defp valid_type("drivers_license"), do: {:ok, "cnh"}
  defp valid_type("rg"), do: {:ok, "rg"}
  defp valid_type(_), do: {:error, :invalid_request}
  defp valid_country("BR"), do: {:ok, "BR"}
  defp valid_country("BRA"), do: {:ok, "BR"}
  defp valid_country(_), do: {:error, :invalid_request}

  defp request_id(conn),
    do: List.first(Plug.Conn.get_resp_header(conn, "x-request-id")) || Ecto.UUID.generate()

  defp idempotency_key(conn), do: List.first(Plug.Conn.get_req_header(conn, "idempotency-key"))
end
