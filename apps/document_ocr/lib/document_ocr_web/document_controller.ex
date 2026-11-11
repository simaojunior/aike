defmodule DocumentOcrWeb.DocumentController do
  @moduledoc "Thin document actions with centralized error responses."
  use DocumentOcrWeb, :controller
  action_fallback(DocumentOcrWeb.FallbackController)
  alias DocumentOcr.{Completion, Documents}
  alias DocumentOcrWeb.{DocumentInput, DocumentJSON, Preference}

  plug(DocumentOcrWeb.ValidateParams,
    create: &DocumentOcrWeb.Schemas.DocumentParams.create/1,
    reprocess: &DocumentOcrWeb.Schemas.DocumentParams.reprocess/1,
    show: &DocumentOcrWeb.Schemas.DocumentParams.resource/1,
    cancel: &DocumentOcrWeb.Schemas.DocumentParams.resource/1
  )

  def create(conn, params) do
    with {:ok, attrs, uploads} <- DocumentInput.attributes(params, conn),
         {:ok, %{document: document} = creation} <- create_document(attrs, uploads) do
      created(conn, document, Map.get(creation, :reused, false))
    end
  end

  defp create_document(attrs, []), do: Documents.create_document(attrs)
  defp create_document(attrs, uploads), do: Documents.create_document_from_uploads(attrs, uploads)
  defp created(conn, document, true), do: render_document(conn, 200, DocumentJSON.data(document))

  defp created(conn, document, false), do: answer(conn, document, Preference.wait(conn))

  defp answer(conn, document, nil), do: accepted(conn, document)

  defp answer(conn, document, seconds) do
    conn = put_resp_header(conn, "preference-applied", "wait=#{seconds}")

    case Completion.await(document.id, seconds * 1_000) do
      {:ok, finished} -> render_document(conn, 200, DocumentJSON.data(finished))
      :timeout -> accepted(conn, Documents.get_document(document.id) || document)
    end
  end

  defp accepted(conn, document) do
    conn
    |> put_resp_header("location", "/v1/extractions/#{document.id}")
    |> render_document(202, DocumentJSON.data(document))
  end

  def reprocess(conn, %{"id" => id, "pipeline_version" => version})
      when is_binary(id) and is_binary(version) do
    request_id = List.first(get_resp_header(conn, "x-request-id")) || Ecto.UUID.generate()

    with {:ok, document} <- Documents.reprocess_document(id, version, request_id),
         do: render_document(conn, 202, DocumentJSON.data(document))
  end

  def reprocess(_conn, _), do: {:error, :invalid_request}

  def cancel(conn, %{"id" => id}) when is_binary(id) do
    with {:ok, document} <- Documents.cancel_document(id),
         do: render_document(conn, 200, DocumentJSON.data(document))
  end

  def cancel(_conn, _), do: {:error, :invalid_request}

  def show(conn, %{"id" => id}) when is_binary(id),
    do: show_document(conn, Documents.get_document(id))

  def show(_conn, _), do: {:error, :invalid_request}
  defp show_document(_conn, nil), do: {:error, :not_found}
  defp show_document(conn, document), do: render_document(conn, 200, DocumentJSON.data(document))

  defp render_document(conn, status, body),
    do: conn |> put_status(status) |> json(body)
end
