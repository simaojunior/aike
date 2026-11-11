defmodule DocumentOcr.Workers.PreprocessDocument do
  @moduledoc """
  Oban worker for the preprocess stage of the OCR pipeline.

  It runs the stage in `DocumentOcr.Workers.Pipeline`. Oban keeps one job for each document
  run.
  """
  use Oban.Worker,
    queue: :preprocess,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  alias DocumentOcr.Workers.Pipeline

  @impl true
  def perform(job), do: Pipeline.perform(:preprocess, job)
end
