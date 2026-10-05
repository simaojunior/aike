defmodule DocumentOcrWeb.Observability do
  import Plug.Conn
  require Logger
  alias KycCore.Observability, as: Obs

  def init(opts), do: opts

  def call(conn, _opts) do
    request_id = List.first(get_req_header(conn, "x-request-id")) || Ecto.UUID.generate()

    Logger.metadata(
      request_id: request_id,
      service: "document_ocr",
      app_id: conn.assigns[:company_id],
      service_account_id: conn.assigns[:service_account_id]
    )

    conn
    |> assign(:aike_started_at, System.monotonic_time())
    |> put_resp_header("x-request-id", request_id)
    |> register_before_send(&log_completed(&1, request_id))
  end

  defp log_completed(conn, request_id) do
    status = conn.status || 200
    duration_ms = System.convert_time_unit(System.monotonic_time() - conn.assigns[:aike_started_at], :native, :millisecond)

    Logger.log(Obs.log_level(status), "HTTP request completed",
      event: "http.request.completed",
      request_id: request_id,
      service: "document_ocr",
      status: status,
      status_class: Obs.status_class(status),
      duration_ms: duration_ms,
      method: conn.method
    )

    conn
  end
end
