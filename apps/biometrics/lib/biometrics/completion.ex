defmodule Biometrics.Completion do
  @moduledoc """
  Lets a facematch request wait for its comparison to finish (`prefer: wait=N`).

  A finished comparison publishes `facematch_completed` through `Oban.Notifier`, which uses
  Postgres `LISTEN/NOTIFY`: the notice leaves only when the transaction commits, and it
  reaches every node without an Erlang cluster. Waiting requests also read the session
  every `completion_poll_ms`, so a lost notice only delays the answer.

  A node accepts at most `max_waiting_requests` waiting requests; past that, `await/2`
  returns at once and the client gets `202`.

  ## Configuration

      config :biometrics,
        max_wait_seconds: 10,
        completion_poll_ms: 1_000,
        max_waiting_requests: 1_000

  ## Examples

      :ok = Biometrics.Completion.notify(session)
      {:ok, session} = Biometrics.Completion.await(session.id, 10_000)
  """
  use GenServer

  alias Biometrics.Facematches.FacematchRepo

  @registry Biometrics.Completion.Registry
  @channel :facematch_completed
  @final_statuses ~w(completed failed)

  @doc """
  Starts the listener.

  ## Parameters
    - opts: ignored

  ## Returns
    - `{:ok, pid}` or an error from `GenServer.start_link/3`
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Publishes that a session reached a final status. Call it inside the transaction that
  changes the status; other statuses publish nothing.

  ## Parameters
    - session: the session after the change

  ## Returns
    - `:ok`
  """
  @spec notify(map()) :: :ok
  def notify(%{status: status, id: id}) when status in @final_statuses do
    Oban.Notifier.notify(Biometrics.Oban, @channel, %{"id" => id})
  end

  def notify(_session), do: :ok

  @doc """
  Waits until a session reaches a final status.

  ## Parameters
    - id: the session ID
    - timeout_ms: the longest wait, in milliseconds

  ## Returns
    - `{:ok, session}` when it finished in time
    - `:timeout` when it did not, or when the node has too many waiting requests
  """
  @spec await(Ecto.UUID.t(), non_neg_integer()) :: {:ok, map()} | :timeout
  def await(id, timeout_ms) do
    max = Application.get_env(:biometrics, :max_waiting_requests, 1_000)
    wait(Registry.count(@registry) < max, id, timeout_ms)
  end

  defp wait(false, _id, _timeout_ms), do: :timeout

  defp wait(true, id, timeout_ms) do
    {:ok, _} = Registry.register(@registry, id, nil)

    try do
      poll(id, System.monotonic_time(:millisecond) + timeout_ms)
    after
      Registry.unregister(@registry, id)
    end
  end

  defp poll(id, deadline) do
    case FacematchRepo.get(id) do
      %{status: status} = session when status in @final_statuses -> {:ok, session}
      _ -> sleep(id, deadline, deadline - System.monotonic_time(:millisecond))
    end
  end

  defp sleep(_id, _deadline, remaining) when remaining <= 0, do: :timeout

  defp sleep(id, deadline, remaining) do
    interval = Application.get_env(:biometrics, :completion_poll_ms, 1_000)

    receive do
      {@channel, ^id} -> poll(id, deadline)
    after
      min(interval, remaining) -> poll(id, deadline)
    end
  end

  @impl true
  def init(:ok) do
    :ok = Oban.Notifier.listen(Biometrics.Oban, [@channel])
    {:ok, nil}
  end

  @impl true
  def handle_info({:notification, @channel, %{"id" => id}}, state) do
    Registry.dispatch(@registry, id, fn waiters ->
      Enum.each(waiters, fn {pid, _} -> send(pid, {@channel, id}) end)
    end)

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
