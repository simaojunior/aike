defmodule DocumentOcr.ErrorResponseTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  test "returns a useful contract for malformed JSON" do
    conn =
      conn(:post, "/v1/extractions", ~s({"name":"Konoha",}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-request-id", "req-malformed-json")
      |> DocumentOcrWeb.Endpoint.call([])

    assert conn.status == 400

    assert Jason.decode!(conn.resp_body) == %{
             "id" => "req-malformed-json",
             "code" => "invalid_json",
             "detail" => "Request body must be valid JSON."
           }

    assert get_resp_header(conn, "x-request-id") == ["req-malformed-json"]
    assert get_resp_header(conn, "content-type") == ["application/problem+json; charset=utf-8"]
  end
end
