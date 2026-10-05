defmodule DocumentOcr.ExternalCall do
  @moduledoc "Runs adapter calls with a bounded wait and no caller link."

  def run(fun, timeout_ms) when is_function(fun, 0) and is_integer(timeout_ms) do
    task = Task.async(fun)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, value} -> value
      {:exit, reason} -> {:error, {:external_exit, reason}}
      nil -> {:error, :timeout}
    end
  end

  def run(fun, _timeout_ms, :sync) when is_function(fun, 0), do: fun.()
  def run(fun, timeout_ms, :async), do: run(fun, timeout_ms)
end
