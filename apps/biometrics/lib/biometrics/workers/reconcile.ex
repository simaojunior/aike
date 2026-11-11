defmodule Biometrics.Workers.Reconcile do
  @moduledoc "Repairs exhausted comparisons and retries local storage cleanup."
  use Oban.Worker,
    queue: :biometrics_maintenance,
    max_attempts: 5,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  @impl true
  def perform(_job) do
    with {:ok, repaired} <- Biometrics.Reconciliation.run(),
         {:ok, counts} <- AikeStorage.Reconciliation.run(Biometrics.BlobOwner.owner()) do
      :telemetry.execute(
        [:aike, :biometrics, :reconciliation],
        Map.put(counts, :repaired, repaired),
        %{}
      )

      :ok
    end
  end
end
