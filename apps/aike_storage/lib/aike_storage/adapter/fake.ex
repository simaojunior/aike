defmodule AikeStorage.Adapter.Fake do
  @moduledoc """
  In-memory storage adapter for tests.

  It keeps the objects in an ETS table. Do not use it outside the test environment.
  """
  @behaviour AikeStorage.Adapter

  @table :aike_storage_fake_objects

  @impl true
  def put(data, opts) when is_binary(data) do
    folder = Keyword.get(opts, :folder, "kyc_documents")
    sha256 = Keyword.fetch!(opts, :sha256)
    extension = Keyword.fetch!(opts, :extension)
    key = "#{folder}/#{sha256}.#{extension}"
    :ets.insert(table(), {key, data})
    {:ok, key}
  end

  @impl true
  def get(key) do
    case :ets.lookup(table(), key) do
      [{^key, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def delete(key) do
    :ets.delete(table(), key)
    :ok
  end

  def reset do
    :ets.delete_all_objects(table())
    :ok
  end

  defp table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, read_concurrency: true])
      tid -> tid
    end
  end
end
