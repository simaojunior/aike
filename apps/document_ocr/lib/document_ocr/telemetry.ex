defmodule DocumentOcr.Telemetry do
  import Ecto.Query

  @event [:aike, :document, :stage]

  def execute(stage, document, fun) do
    started = System.monotonic_time()

    try do
      result = fun.()
      emit(stage, document, started, result)
      result
    rescue
      error ->
        emit(stage, document, started, {:error, :exception})
        reraise error, __STACKTRACE__
    end
  end

  @doc "Returns the number of pending or executing jobs in an Oban queue."
  @spec queue_depth(atom() | String.t()) :: non_neg_integer()
  def queue_depth(queue) do
    queue = to_string(queue)

    from(job in Oban.Job,
      where:
        job.queue == ^queue and job.state in ["available", "scheduled", "executing", "retryable"]
    )
    |> DocumentOcr.Repo.aggregate(:count)
  end

  defp emit(stage, document, started, result) do
    duration = System.monotonic_time() - started

    :telemetry.execute(
      @event,
      %{
        duration: duration,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond)
      },
      %{stage: stage, document_id: document.id, app_id: document.app_id, outcome: outcome(result)}
    )
  end

  defp outcome(:ok), do: :ok
  defp outcome({:cancel, reason}), do: {:cancel, reason}
  defp outcome({:error, _}), do: :error
  defp outcome(_), do: :unknown
end
