defmodule AikeAuth.CacheTest do
  use ExUnit.Case, async: false
  alias AikeAuth.Cache

  @identity %{account_id: "account", company_id: "tenant", scopes: ["ocr:write"]}

  setup do
    previous = Application.get_env(:aike_auth, :cache_ttl_seconds)
    Application.put_env(:aike_auth, :cache_ttl_seconds, 30)
    on_exit(fn -> Application.put_env(:aike_auth, :cache_ttl_seconds, previous) end)
    %{account: "account-#{System.unique_integer([:positive])}"}
  end

  defp counting(result) do
    counter = :counters.new(1, [])

    lookup = fn ->
      :counters.add(counter, 1, 1)
      Process.sleep(50)
      result
    end

    {lookup, fn -> :counters.get(counter, 1) end}
  end

  test "a valid identity is reused and concurrent misses share one lookup", %{account: account} do
    {lookup, calls} = counting({:ok, @identity})

    results =
      1..50
      |> Task.async_stream(fn _ -> Cache.fetch(account, "secret", lookup) end,
        max_concurrency: 50
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &(&1 == {:ok, @identity}))
    assert Cache.fetch(account, "secret", lookup) == {:ok, @identity}
    assert calls.() == 1
  end

  test "a different secret for the same account is not served from the cache", %{account: account} do
    {lookup, _} = counting({:ok, @identity})
    assert {:ok, _} = Cache.fetch(account, "secret", lookup)
    {denied, calls} = counting({:error, :unauthorized})
    assert {:error, :unauthorized} = Cache.fetch(account, "wrong", denied)
    assert calls.() == 1
  end

  test "denials and outages are not cached", %{account: account} do
    for result <- [{:error, :unauthorized}, {:error, :unavailable}] do
      {lookup, calls} = counting(result)
      assert Cache.fetch(account, "secret", lookup) == result
      assert Cache.fetch(account, "secret", lookup) == result
      assert calls.() == 2
    end
  end

  test "a lookup that raises is an outage for every waiter", %{account: account} do
    assert {:error, :unavailable} = Cache.fetch(account, "secret", fn -> raise "boom" end)
  end

  test "a ttl of zero disables the cache", %{account: account} do
    Application.put_env(:aike_auth, :cache_ttl_seconds, 0)
    {lookup, calls} = counting({:ok, @identity})
    Cache.fetch(account, "secret", lookup)
    Cache.fetch(account, "secret", lookup)
    assert calls.() == 2
  end

  test "the cache keeps no secret" do
    Cache.fetch("account-secret-check", "very-secret-value", fn -> {:ok, @identity} end)
    refute inspect(:ets.tab2list(AikeAuth.Cache)) =~ "very-secret-value"
  end
end
