defmodule AikeHttp.HealthTest do
  use ExUnit.Case, async: true
  import Plug.Test

  test "answers GET and HEAD /health and halts" do
    for method <- [:get, :head] do
      conn = AikeHttp.Health.call(conn(method, "/health"), [])
      assert conn.status == 200
      assert conn.halted
    end

    assert AikeHttp.Health.call(conn(:get, "/health"), []).resp_body == ~s({"status":"ok"})
  end

  test "passes other requests through" do
    for {method, path} <- [{:get, "/v1/extractions"}, {:post, "/health"}, {:get, "/health/db"}] do
      conn = AikeHttp.Health.call(conn(method, path), [])
      refute conn.halted
      assert conn.status == nil
    end
  end
end
