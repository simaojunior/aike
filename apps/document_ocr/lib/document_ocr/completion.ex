defmodule DocumentOcr.Completion do
  @moduledoc """
  Lets a request wait for an extraction to reach a final status (`prefer: wait=N`).

  A status change publishes `extraction_completed` through `Oban.Notifier`, which uses
  Postgres `LISTEN/NOTIFY`: the notice leaves only when the transaction commits, and it
  reaches every node without an Erlang cluster. This process listens and forwards each
  notice to the requests waiting for that document. Waiting requests also read the
  document every `completion_poll_ms`, so a lost notice only delays the answer.

  A node accepts at most `max_waiting_requests` waiting requests; past that, `await/2`
  returns at once and the client gets `202`, which keeps a traffic peak from holding
  thousands of connections.

  ## Configuration

      config :document_ocr,
        completion_poll_ms: 1_000,
        max_waiting_requests: 1_000

  ## Examples

      :ok = DocumentOcr.Completion.notify(document)
      {:ok, document} = DocumentOcr.Completion.await(document.id, 10_000)
  """
  use GenServer

  alias DocumentOcr.Documents

  @registry DocumentOcr.Completion.Registry
  @channel :extraction_completed
  @final_statuses ~w(completed requires_confirmation rejected failed)

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
  Publishes that a document reached a final status.

  Call it inside the transaction that changes the status: the notice leaves on commit.
  Statuses that are not final publish nothing.

  ## Parameters
    - document: the document after the change

  ## Returns
    - `:ok`
  """
  @spec notify(map()) :: :ok
  def notify(%{status: status, id: id}) when status in @final_statuses do
    Oban.Notifier.notify(Oban, @channel, %{"id" => id})
  end

  def notify(_document), do: :ok

  @doc """
  Waits until a document reaches a final status.

  ## Parameters
    - id: the document ID
    - timeout_ms: the longest wait, in milliseconds

  ## Returns
    - `{:ok, document}` when the document reached a final status in time
    - `:timeout` when it did not, or when the node already has too many waiting requests
  """
  @spec await(Ecto.UUID.t(), non_neg_integer()) :: {:ok, map()} | :timeout
  def await(id, timeout_ms) do
    max = Application.get_env(:document_ocr, :max_waiting_requests, 1_000)
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
    case Documents.get_document(id) do
      %{status: status} = document when status in @final_statuses -> {:ok, document}
      _ -> sleep(id, deadline, deadline - System.monotonic_time(:millisecond))
    end
  end

  defp sleep(_id, _deadline, remaining) when remaining <= 0, do: :timeout

  defp sleep(id, deadline, remaining) do
    interval = Application.get_env(:document_ocr, :completion_poll_ms, 1_000)

    receive do
      {@channel, ^id} -> poll(id, deadline)
    after
      min(interval, remaining) -> poll(id, deadline)
    end
  end

  @impl true
  def init(:ok) do
    :ok = Oban.Notifier.listen(Oban, [@channel])
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
