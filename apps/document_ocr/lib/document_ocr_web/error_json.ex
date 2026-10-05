defmodule DocumentOcrWeb.ErrorJSON do
  @moduledoc "Structured JSON errors for the OCR HTTP boundary."

  import Plug.Conn, only: [get_req_header: 2]

  @spec render(String.t(), map()) :: map()
  def render("400.json", %{reason: %Plug.Parsers.ParseError{}, conn: conn}) do
    error("invalid_json", "Request body must be valid JSON.", request_id(conn))
  end

  def render(template, assigns) do
    error(
      status_code(template),
      Phoenix.Controller.status_message_from_template(template),
      request_id(assigns[:conn])
    )
  end

  defp error(code, message, request_id),
    do: %{error: %{code: code, message: message, requestId: request_id}}

  defp status_code(template) do
    template
    |> Phoenix.Controller.status_message_from_template()
    |> String.downcase()
    |> String.replace(" ", "_")
  end

  defp request_id(nil), do: nil
  defp request_id(conn), do: List.first(get_req_header(conn, "x-request-id"))
end
