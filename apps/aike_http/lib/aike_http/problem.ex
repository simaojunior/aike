defmodule AikeHttp.Problem do
  @moduledoc """
  The error body shared by every API: `id`, `code`, `detail` and optional field `errors`.

  `id` is the request ID (the `x-request-id` header and the `request_id` log field), so a
  client can quote it when it reports a problem. It is left out when no request is running.
  The body is sent as `application/problem+json` with `cache-control: no-store`.

  ## Examples

      AikeHttp.Problem.send(conn, 404, "not_found")
  """
  import Plug.Conn

  @details %{
    "validation" => "One or more request fields are invalid.",
    "conflict" => "The request conflicts with an existing resource.",
    "method_not_allowed" => "The HTTP method is not supported for this resource.",
    "not_acceptable" => "The requested response format is not supported.",
    "invalid_request" => "The request is invalid.",
    "unauthorized" => "Authentication is required or the credentials are invalid.",
    "invalid_credentials" => "Email or password is invalid.",
    "forbidden" => "You do not have permission to perform this operation.",
    "not_found" => "The requested resource was not found.",
    "company_not_found" => "An active company was not found.",
    "already_bootstrapped" => "The first administrator already exists. Use the login endpoint.",
    "last_platform_admin" => "The last active platform administrator cannot be removed.",
    "invalid_password" => "Password must contain at least 15 characters and at most 1024 bytes.",
    "rate_limited" => "Too many requests. Retry after the interval in Retry-After.",
    "bad_request" => "The request body is malformed.",
    "invalid_json" => "Request body must be valid JSON.",
    "payload_too_large" => "The request body exceeds the allowed size.",
    "unsupported_media_type" => "The request content type is not supported.",
    "unsupported_file" => "Send a JPEG, PNG or single-page PDF.",
    "image_too_large" =>
      "The image resolution is too high. Send a JPEG, or a PNG up to 20 megapixels.",
    "unsupported_page_count" => "The PDF must have exactly one page.",
    "file_too_large" => "The file exceeds 10 MB.",
    "idempotency_conflict" => "This idempotency key is already bound to a different request.",
    "invalid_pipeline_version" => "The requested pipeline version is invalid.",
    "document_not_cancellable" => "The document cannot be cancelled in its current state.",
    "service_unavailable" => "The service is temporarily unavailable.",
    "internal_server_error" => "Internal server error."
  }

  @doc """
  Builds an error body.

  ## Parameters
    - code: a registered error code
    - errors: optional list of `%{field: ..., detail: ...}`

  ## Returns
    - a `Jason.OrderedObject` with `id` (when known), `code`, `detail` and `errors`
  """
  @spec body(String.t(), [map()] | nil) :: Jason.OrderedObject.t()
  def body(code, errors \\ nil) do
    fields =
      id_field(Logger.metadata()[:request_id]) ++ [code: code, detail: Map.fetch!(@details, code)]

    fields =
      if is_list(errors) do
        issues = Enum.map(errors, &Jason.OrderedObject.new(field: &1.field, detail: &1.detail))
        fields ++ [errors: issues]
      else
        fields
      end

    Jason.OrderedObject.new(fields)
  end

  @doc """
  Sends an error response.

  ## Parameters
    - conn: the connection
    - status: the HTTP status
    - code: a registered error code
    - errors: optional field errors

  ## Returns
    - the sent connection
  """
  @spec send(Plug.Conn.t(), pos_integer(), String.t(), [map()] | nil) :: Plug.Conn.t()
  def send(conn, status, code, errors \\ nil) do
    body = body(code, errors)

    conn
    |> put_resp_content_type("application/problem+json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, Jason.encode!(body))
  end

  @doc "Sends a `422 validation` response built from Peri errors."
  @spec validation(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def validation(conn, errors),
    do: send(conn, 422, "validation", AikeHttp.FieldIssues.from_peri(errors))

  @template_codes %{
    400 => "bad_request",
    401 => "unauthorized",
    403 => "forbidden",
    404 => "not_found",
    405 => "method_not_allowed",
    406 => "not_acceptable",
    413 => "payload_too_large",
    415 => "unsupported_media_type",
    422 => "validation",
    429 => "rate_limited",
    503 => "service_unavailable"
  }

  @doc "Builds the error body for a Phoenix error template such as `\"404.json\"`."
  @spec from_template(String.t()) :: Jason.OrderedObject.t()
  def from_template(template) do
    status = template |> String.split(".") |> hd() |> String.to_integer()

    body(Map.get(@template_codes, status, "internal_server_error"))
  end

  defp id_field(nil), do: []
  defp id_field(id), do: [id: id]
end
