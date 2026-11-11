defmodule AikeVision.Limiter do
  @moduledoc """
  Counting semaphore with a bounded, time-limited waiting line.

  A holder that exits releases its slot. A full line, or a wait past its deadline, returns
  `{:error, :overloaded}` at once, so a traffic peak is refused fast instead of piling up
  memory and timeouts. Emits `[:aike_vision, :limiter, :acquired]` (with the wait time)
  and `[:aike_vision, :limiter, :rejected]`.

  ## Configuration

  Started by `AikeVision.Application` as `AikeVision.Processes` and
  `AikeVision.Documents`. A custom one:

      {AikeVision.Limiter, name: MyLimiter, limit: 4, max_waiting: 8}

  ## Examples

      AikeVision.Limiter.run(AikeVision.Documents, fn -> classify(bytes) end, 3_000)
  """
  use GenServer

  @type option ::
          {:name, atom()} | {:limit, pos_integer()} | {:max_waiting, non_neg_integer() | :infinity}

  @doc """
  Starts a limiter.

  ## Parameters
    - opts: `:name` (required), `:limit` (required), `:max_waiting` (default
      `:infinity`)

  ## Returns
    - `{:ok, pid}` or an error from `GenServer.start_link/3`
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  def child_spec(opts),
    do: %{id: Keyword.fetch!(opts, :name), start: {__MODULE__, :start_link, [opts]}}

  @doc """
  Runs `fun` while holding a slot.

  ## Parameters
    - limiter: the limiter name
    - fun: the work to run
    - wait_ms: longest wait for a slot, in milliseconds, or `:infinity`

  ## Returns
    - the value returned by `fun`
    - `{:error, :overloaded}` when the line is full or the wait passes its deadline

  ## Example

      {:error, :overloaded} = AikeVision.Limiter.run(AikeVision.Documents, work, 0)
  """
  @spec run(atom(), (-> result), timeout()) :: result | {:error, :overloaded} when result: term()
  def run(limiter, fun, wait_ms) do
    case GenServer.call(limiter, {:acquire, wait_ms}, :infinity) do
      {:ok, slot} ->
        try do
          fun.()
        after
          GenServer.cast(limiter, {:release, slot})
        end

      {:error, :overloaded} ->
        {:error, :overloaded}
    end
  end

  @doc """
  Tells whether a new caller would be refused at once.

  ## Parameters
    - limiter: the limiter name

  ## Returns
    - `true` when every slot is in use and the waiting line is full
  """
  @spec saturated?(atom()) :: boolean()
  def saturated?(limiter), do: GenServer.call(limiter, :saturated?)

  @doc """
  Current use of a limiter.

  ## Parameters
    - limiter: the limiter name

  ## Returns
    - `%{limit: slots, in_use: busy_slots, waiting: callers_in_line}`
  """
  @spec stats(atom()) :: %{limit: pos_integer(), in_use: non_neg_integer(), waiting: non_neg_integer()}
  def stats(limiter), do: GenServer.call(limiter, :stats)

  @impl true
  def init(opts) do
    {:ok,
     %{
       name: Keyword.fetch!(opts, :name),
       limit: Keyword.fetch!(opts, :limit),
       max_waiting: Keyword.get(opts, :max_waiting, :infinity),
       holders: %{},
       waiting: :queue.new(),
       waiting_count: 0
     }}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, %{limit: state.limit, in_use: map_size(state.holders), waiting: state.waiting_count},
     state}
  end

  def handle_call(:saturated?, _from, state),
    do: {:reply, map_size(state.holders) >= state.limit and full?(state), state}

  def handle_call({:acquire, wait_ms}, {pid, _} = from, state) do
    cond do
      map_size(state.holders) < state.limit and state.waiting_count == 0 ->
        slot = Process.monitor(pid)
        emit(:acquired, state, 0)
        {:reply, {:ok, slot}, %{state | holders: Map.put(state.holders, slot, pid)}}

      wait_ms == 0 or full?(state) ->
        emit(:rejected, state, 0)
        {:reply, {:error, :overloaded}, state}

      true ->
        slot = Process.monitor(pid)
        waiter = {from, slot, expiry(wait_ms, slot), System.monotonic_time()}

        {:noreply,
         %{state | waiting: :queue.in(waiter, state.waiting), waiting_count: state.waiting_count + 1}}
    end
  end

  @impl true
  def handle_cast({:release, slot}, state) do
    Process.demonitor(slot, [:flush])
    {:noreply, state |> drop_holder(slot) |> grant()}
  end

  @impl true
  def handle_info({:DOWN, slot, :process, _, _}, %{holders: holders} = state)
      when is_map_key(holders, slot),
      do: {:noreply, state |> drop_holder(slot) |> grant()}

  def handle_info({:DOWN, slot, :process, _, _}, state),
    do: {:noreply, drop_waiter(state, slot, nil)}

  def handle_info({:expire, slot}, state) do
    {:noreply, drop_waiter(state, slot, {:error, :overloaded})}
  end

  defp full?(%{max_waiting: :infinity}), do: false
  defp full?(state), do: state.waiting_count >= state.max_waiting

  defp drop_holder(state, slot), do: %{state | holders: Map.delete(state.holders, slot)}

  defp drop_waiter(state, slot, reply) do
    {matching, rest} =
      state.waiting |> :queue.to_list() |> Enum.split_with(fn {_, s, _, _} -> s == slot end)

    Enum.each(matching, fn {from, _, timer, _} ->
      cancel(timer)
      Process.demonitor(slot, [:flush])
      refuse(reply, from, state)
    end)

    %{state | waiting: :queue.from_list(rest), waiting_count: length(rest)}
  end

  defp grant(state) do
    with true <- map_size(state.holders) < state.limit,
         {{:value, {from, slot, timer, since}}, waiting} <- :queue.out(state.waiting) do
      cancel(timer)
      emit(:acquired, state, System.monotonic_time() - since)
      GenServer.reply(from, {:ok, slot})

      grant(%{
        state
        | holders: Map.put(state.holders, slot, elem(from, 0)),
          waiting: waiting,
          waiting_count: state.waiting_count - 1
      })
    else
      _ -> state
    end
  end

  defp expiry(:infinity, _slot), do: nil
  defp expiry(wait_ms, slot), do: Process.send_after(self(), {:expire, slot}, wait_ms)

  defp cancel(nil), do: :ok
  defp cancel(timer), do: Process.cancel_timer(timer)

  defp refuse(nil, _from, _state), do: :ok

  defp refuse(reply, from, state) do
    emit(:rejected, state, 0)
    GenServer.reply(from, reply)
  end

  defp emit(event, state, wait) do
    :telemetry.execute(
      [:aike_vision, :limiter, event],
      %{wait: wait, in_use: map_size(state.holders), waiting: state.waiting_count},
      %{limiter: state.name}
    )
  end
end
