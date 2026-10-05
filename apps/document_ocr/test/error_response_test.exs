defmodule DocumentOcr.ErrorResponseTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  test "returns a useful contract for malformed JSON" do
    conn =
      conn(:post, "/v1/companies", ~s({"name":"Acme",}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-request-id", "req-malformed-json")
      |> DocumentOcrWeb.Endpoint.call([])

    assert conn.status == 400

    assert %{
             "error" => %{
               "code" => "invalid_json",
               "message" => "Request body must be valid JSON.",
               "requestId" => "req-malformed-json"
             }
           } = Jason.decode!(conn.resp_body)
  end
end
