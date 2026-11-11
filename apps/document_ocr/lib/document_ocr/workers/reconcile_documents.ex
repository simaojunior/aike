defmodule DocumentOcr.Workers.ReconcileDocuments do
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
