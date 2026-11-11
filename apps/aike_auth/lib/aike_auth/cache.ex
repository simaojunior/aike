defmodule AikeAuth.Cache do
  @moduledoc """
  Short-lived cache of validated service identities.

  Without it, a traffic peak sends one introspection request per API request to the
  backoffice. Keys are an HMAC of the credentials with a key created at boot, so secrets
  never stay in memory and the keys are useless outside this node and boot. Only valid
  identities are kept: denials and outages are not cached, so a new account works at once
  and a backoffice outage does not persist. Concurrent misses for the same credentials
  share one lookup. Emits `[:aike_auth, :cache, :hit]` and `[:aike_auth, :cache, :miss]`.

  A revoked credential keeps working on each node for at most `cache_ttl_seconds`.

  ## Configuration

      config :aike_auth, cache_ttl_seconds: 30

  `0` disables the cache. In releases, set it with `AIKE_AUTH_CACHE_TTL_SECONDS` (0 to 300).

  ## Examples

      AikeAuth.Cache.fetch(account_id, secret, fn -> introspect(account_id, secret) end)
  """
  use GenServer

  @table __MODULE__
  @max_entries 10_000

  @doc """
  Starts the cache and creates its key for this boot.

  ## Parameters
    - opts: ignored

  ## Returns
    - `{:ok, pid}` or an error from `GenServer.start_link/3`
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Returns the cached identity, or runs `lookup` once for all concurrent callers.

  ## Parameters
    - account_id: the service account ID
    - secret: the service account secret
    - lookup: function that asks the backoffice and returns `{:ok, identity}` or
      `{:error, reason}`

  ## Returns
    - `{:ok, identity}` from the cache or from `lookup`
    - `{:error, reason}` from `lookup` (never cached); `{:error, :unavailable}` when
      `lookup` raises

  ## Example

      {:ok, %{company_id: company_id}} =
        AikeAuth.Cache.fetch("svc_konoha", secret, fn -> AikeAuth.HTTP.authenticate("svc_konoha", secret) end)
  """
  @spec fetch(String.t(), String.t(), (-> {:ok, map()} | {:error, atom()})) ::
          {:ok, map()} | {:error, atom()}
  def fetch(account_id, secret, lookup) do
    case ttl_ms() do
      0 -> lookup.()
      ttl -> cached(key(account_id, secret), lookup, ttl)
    end
  end

  defp cached(key, lookup, ttl) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, identity, expires_at}] when expires_at > now ->
        :telemetry.execute([:aike_auth, :cache, :hit], %{count: 1}, %{})
        {:ok, identity}

      _ ->
        :telemetry.execute([:aike_auth, :cache, :miss], %{count: 1}, %{})
        GenServer.call(__MODULE__, {:resolve, key, lookup, ttl}, 10_000)
    end
  end

  defp key(account_id, secret) do
    :crypto.mac(:hmac, :sha256, :persistent_term.get({__MODULE__, :key}), [
      account_id,
      0,
      secret
    ])
  end

  defp ttl_ms, do: Application.get_env(:aike_auth, :cache_ttl_seconds, 30) * 1000

  @impl true
  def init(:ok) do
    :persistent_term.put({__MODULE__, :key}, :crypto.strong_rand_bytes(32))
    :ets.new(@table, [:named_table, :protected, read_concurrency: true])
    schedule_sweep()
    {:ok, %{pending: %{}}}
  end

  @impl true
  def handle_call({:resolve, key, lookup, ttl}, from, state) do
    case state.pending do
      %{^key => waiters} ->
        {:noreply, put_in(state.pending[key], [from | waiters])}

      _ ->
        server = self()
        spawn(fn -> send(server, {:resolved, key, ttl, safe(lookup)}) end)
        {:noreply, put_in(state.pending[key], [from])}
    end
  end

  @impl true
  def handle_info({:resolved, key, ttl, result}, state) do
    with {:ok, identity} <- result, do: store(key, identity, ttl)
    {waiters, pending} = Map.pop(state.pending, key, [])
    Enum.each(waiters, &GenServer.reply(&1, result))
    {:noreply, %{state | pending: pending}}
  end

  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp store(key, identity, ttl), do: store(:ets.info(@table, :size), key, identity, ttl)

  defp store(size, key, identity, ttl) when size < @max_entries,
    do: :ets.insert(@table, {key, identity, System.monotonic_time(:millisecond) + ttl})

  defp store(_size, _key, _identity, _ttl), do: false

  defp safe(lookup) do
    lookup.()
  rescue
    _ -> {:error, :unavailable}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, 60_000)
end
