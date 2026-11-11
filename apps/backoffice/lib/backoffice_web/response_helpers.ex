defmodule BackofficeWeb.ResponseHelpers do
  @moduledoc "Stable backoffice errors, preserving the documented error envelope."
  import Plug.Conn

  @errors %{
    unauthorized: {401, "unauthorized"},
    invalid_credentials: {401, "invalid_credentials"},
    refresh_token_reused: {401, "unauthorized"},
    forbidden: {403, "forbidden"},
    not_found: {404, "not_found"},
    company_not_found: {404, "company_not_found"},
    already_bootstrapped: {409, "already_bootstrapped"},
    last_platform_admin: {409, "last_platform_admin"},
    invalid_request: {422, "invalid_request"},
    invalid_password: {422, "invalid_password"},
    rate_limited: {429, "rate_limited"},
    bad_request: {400, "bad_request"},
    invalid_json: {400, "invalid_json"},
    payload_too_large: {413, "payload_too_large"},
    unsupported_media_type: {415, "unsupported_media_type"}
  }
  @spec error_info(atom()) :: {integer(), String.t()}
  def error_info(reason), do: Map.fetch!(@errors, reason)

  def render_error(conn, reason) do
    {status, code} = error_info(reason)
    conn |> response_headers(status) |> AikeHttp.Problem.send(status, code)
  end

  def render_validation(conn, %Ecto.Changeset{} = changeset) do
    # Input issues are Peri's responsibility. Database constraints are domain conflicts.
    if Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
         opts[:constraint] == :unique
       end) do
      AikeHttp.Problem.send(conn, 409, "conflict")
    else
      AikeHttp.Problem.send(conn, 422, "invalid_request")
    end
  end

  def render_validation(conn, errors), do: AikeHttp.Problem.validation(conn, errors)

  defp response_headers(conn, 401), do: put_resp_header(conn, "www-authenticate", "Bearer")
  defp response_headers(conn, 429), do: put_resp_header(conn, "retry-after", "300")
  defp response_headers(conn, _), do: conn
end
