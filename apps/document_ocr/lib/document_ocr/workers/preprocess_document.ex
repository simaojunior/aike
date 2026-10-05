defmodule DocumentOcr.Workers.PreprocessDocument do
  use Oban.Worker,
    queue: :preprocess,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  @impl true
  def perform(job), do: DocumentOcr.Workers.Pipeline.perform(:preprocess, job)
end
