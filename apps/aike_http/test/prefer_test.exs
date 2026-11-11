defmodule AikeHttp.PreferTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  defp wait(header, max \\ 10) do
    conn =
      if header, do: put_req_header(conn(:post, "/"), "prefer", header), else: conn(:post, "/")

    AikeHttp.Prefer.wait(conn, max)
  end

  test "reads wait=N and caps it at the maximum" do
    assert wait("wait=5") == 5
    assert wait("respond-async, wait=30") == 10
    assert wait("WAIT=3") == 3
  end

  test "no header, no wait or an invalid wait means no wait" do
    for header <- [nil, "respond-async", "wait=0", "wait=-2", "wait=soon"] do
      assert wait(header) == nil
    end
  end
end
