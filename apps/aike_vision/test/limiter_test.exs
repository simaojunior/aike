defmodule AikeVision.LimiterTest do
  use ExUnit.Case, async: true
  alias AikeVision.Limiter

  defp start(opts) do
    name = :"limiter_#{System.unique_integer([:positive])}"
    start_supervised!({Limiter, [name: name] ++ opts})
    name
  end

  defp hold(limiter, wait \\ 5_000) do
    parent = self()

    Task.async(fn ->
      Limiter.run(
        limiter,
        fn ->
          send(parent, {:holding, self()})

          receive do
            :finish -> :done
          end
        end,
        wait
      )
    end)
  end

  defp holding do
    assert_receive {:holding, pid}, 1_000
    pid
  end

  test "runs up to the limit at once and refuses at once when the line is full" do
    limiter = start(limit: 1, max_waiting: 1)
    first = hold(limiter)
    holder = holding()
    waiting = hold(limiter)
    Process.sleep(20)

    assert %{in_use: 1, waiting: 1} = Limiter.stats(limiter)
    assert {:error, :overloaded} = Limiter.run(limiter, fn -> :never end, 5_000)

    send(holder, :finish)
    assert Task.await(first) == :done
    send(holding(), :finish)
    assert Task.await(waiting) == :done
  end

  test "a wait past its deadline is refused and leaves the line" do
    limiter = start(limit: 1, max_waiting: 10)
    first = hold(limiter)
    holder = holding()

    assert {:error, :overloaded} = Limiter.run(limiter, fn -> :never end, 50)
    assert %{waiting: 0} = Limiter.stats(limiter)

    send(holder, :finish)
    Task.await(first)
  end

  test "a holder that dies releases its slot to the next in line" do
    limiter = start(limit: 1)
    Process.flag(:trap_exit, true)
    first = hold(limiter)
    holder = holding()
    second = hold(limiter)

    Process.exit(first.pid, :kill)
    refute Process.alive?(holder)
    send(holding(), :finish)
    assert Task.await(second) == :done
    assert %{in_use: 0, waiting: 0} = Limiter.stats(limiter)
  end

  test "slots go to waiters in arrival order and are released after errors" do
    limiter = start(limit: 1)
    first = hold(limiter)
    holder = holding()
    parent = self()

    waiters =
      for i <- 1..3 do
        task =
          Task.async(fn -> Limiter.run(limiter, fn -> send(parent, {:ran, i}) end, 5_000) end)

        Process.sleep(10)
        task
      end

    send(holder, :finish)
    Task.await(first)
    Enum.each(waiters, &Task.await/1)

    order =
      for _ <- 1..3 do
        receive do
          {:ran, i} -> i
        end
      end

    assert order == [1, 2, 3]

    assert_raise RuntimeError, fn -> Limiter.run(limiter, fn -> raise "boom" end, 5_000) end
    assert %{in_use: 0} = Limiter.stats(limiter)
  end
end
