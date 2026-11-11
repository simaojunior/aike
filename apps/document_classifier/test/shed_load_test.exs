defmodule DocumentClassifierWeb.ShedLoadTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn
  alias AikeVision.Limiter
  alias DocumentClassifierWeb.ShedLoad

  test "refuses a POST before reading its body only while the waiting line is full" do
    limiter = :"shed_#{System.unique_integer([:positive])}"
    start_supervised!({Limiter, name: limiter, limit: 1, max_waiting: 0})
    opts = ShedLoad.init(limiter: limiter)

    assert %{halted: false} = ShedLoad.call(conn(:post, "/v1/classifications"), opts)

    parent = self()

    holder =
      Task.async(fn ->
        Limiter.run(
          limiter,
          fn ->
            send(parent, :holding)

            receive do
              :finish -> :done
            end
          end,
          1_000
        )
      end)

    assert_receive :holding
    refused = ShedLoad.call(conn(:post, "/v1/classifications"), opts)
    assert refused.halted
    assert refused.status == 503
    assert get_resp_header(refused, "retry-after") == ["2"]
    assert %{halted: false} = ShedLoad.call(conn(:get, "/health"), opts)

    send(holder.pid, :finish)
    Task.await(holder)
    assert %{halted: false} = ShedLoad.call(conn(:post, "/v1/classifications"), opts)
  end
end
