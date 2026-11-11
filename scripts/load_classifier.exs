files =
  "LOAD_FILES"
  |> System.fetch_env!()
  |> String.split(",", trim: true)
  |> Enum.map(&File.read!/1)

requests = String.to_integer(System.get_env("LOAD_REQUESTS", "200"))
started = System.monotonic_time(:millisecond)

results =
  0..(requests - 1)
  |> Task.async_stream(
    fn index ->
      begin = System.monotonic_time(:millisecond)

      result =
        DocumentClassifier.Engine.Tesseract.classify(
          Enum.at(files, rem(index, length(files))),
          []
        )

      outcome = if match?({:ok, _}, result), do: :processed, else: elem(result, 1)
      {outcome, System.monotonic_time(:millisecond) - begin}
    end,
    max_concurrency: requests,
    timeout: :infinity
  )
  |> Enum.map(fn {:ok, result} -> result end)

elapsed = System.monotonic_time(:millisecond) - started

percentile = fn values, fraction ->
  sorted = Enum.sort(values)
  Enum.at(sorted, max(0, min(length(sorted) - 1, round(fraction * length(sorted)) - 1)))
end

for {outcome, latencies} <- Enum.group_by(results, &elem(&1, 0), &elem(&1, 1)) do
  IO.puts(
    "#{outcome}: #{length(latencies)} requests, p50 #{percentile.(latencies, 0.5)} ms, " <>
      "p95 #{percentile.(latencies, 0.95)} ms, max #{Enum.max(latencies)} ms"
  )
end

processed = Enum.count(results, &(elem(&1, 0) == :processed))

IO.puts(
  "elapsed #{elapsed} ms, throughput #{Float.round(processed / max(elapsed, 1) * 1000, 2)} documents/s, " <>
    "limits #{inspect(AikeVision.Limiter.stats(AikeVision.Documents))}"
)
