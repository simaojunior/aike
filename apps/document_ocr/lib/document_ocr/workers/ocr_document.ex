defmodule DocumentOcr.Workers.OcrDocument do
  @moduledoc """
  Oban worker for the OCR stage of the OCR pipeline.

  It runs the stage in `DocumentOcr.Workers.Pipeline`. Oban keeps one job for each document
  run.
  """
  use Oban.Worker,
    queue: :ocr,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  alias DocumentOcr.Workers.Pipeline

  @impl true
  def perform(job), do: Pipeline.perform(:ocr, job)
end
