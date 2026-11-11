defmodule DocumentOcr.Workers.ReconcileDocuments do
  @moduledoc """
  Oban worker that repairs documents with an exhausted job.

  It calls `DocumentOcr.Reconciliation.run/0` and emits a telemetry event with the number of
  repaired documents.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  @impl true
  def perform(_job) do
    case DocumentOcr.Reconciliation.run() do
      {:ok, count} ->
        :telemetry.execute([:aike, :document, :reconciliation], %{repaired: count}, %{})
        :ok

      {:error, _} ->
        {:error, :reconciliation_failed}
    end
  end
end
