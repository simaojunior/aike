defmodule AikeObservability.Queues do
  @moduledoc "Prometheus queue snapshots, without document or tenant labels."
  @states ~w(available scheduled executing retryable completed discarded cancelled)

  def render(repo, service, queues) do
    sql = """
    SELECT queue, state, count(*),
      greatest(0, extract(epoch FROM (CURRENT_TIMESTAMP - min(scheduled_at))))::float8
    FROM oban_jobs
    WHERE queue = ANY($1) AND state = ANY($2)
    GROUP BY queue, state
    """

    with {:ok, %{rows: rows}} <-
           repo.query(sql, [queues, @states], timeout: 5_000, log: false) do
      {:ok, encode(service, queues, rows)}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def encode(service, queues, rows) do
    values = Map.new(rows, fn [queue, state, count, age] -> {{queue, state}, {count, age}} end)

    counts =
      for queue <- queues, state <- @states do
        {count, _} = Map.get(values, {queue, state}, {0, 0})

        "aike_queue_jobs{service=\"#{label(service)}\",queue=\"#{label(queue)}\",state=\"#{state}\"} #{count}\n"
      end

    ages =
      for queue <- queues do
        age =
          ~w(available retryable)
          |> Enum.map(fn state -> values |> Map.get({queue, state}, {0, 0}) |> elem(1) end)
          |> Enum.max()

        "aike_queue_oldest_ready_age_seconds{service=\"#{label(service)}\",queue=\"#{label(queue)}\"} #{age}\n"
      end

    IO.iodata_to_binary([
      "# HELP aike_queue_jobs Current retained Oban jobs by queue and state.\n",
      "# TYPE aike_queue_jobs gauge\n",
      counts,
      "# HELP aike_queue_oldest_ready_age_seconds Age since scheduled time of oldest available or retryable job.\n",
      "# TYPE aike_queue_oldest_ready_age_seconds gauge\n",
      ages
    ])
  end

  defp label(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
    |> String.replace("\"", "\\\"")
  end
end
