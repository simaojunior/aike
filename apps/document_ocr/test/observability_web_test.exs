defmodule DocumentOcrWeb.ObservabilityTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  test "propagates an incoming request id" do
    conn =
      conn(:get, "/v1/extractions")
      |> put_req_header("x-request-id", "req-42")
      |> DocumentOcrWeb.Observability.call([])

    assert get_resp_header(conn, "x-request-id") == ["req-42"]
    assert is_integer(conn.assigns.aike_started_at)
  end

  test "generates a request id when the client omits it" do
    conn = DocumentOcrWeb.Observability.call(conn(:get, "/v1/extractions"), [])
    assert [request_id] = get_resp_header(conn, "x-request-id")
    assert {:ok, _uuid} = Ecto.UUID.cast(request_id)
  end
end
