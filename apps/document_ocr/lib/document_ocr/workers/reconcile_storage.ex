defmodule DocumentOcr.Workers.ReconcileStorage do
  @moduledoc "Periodically retries local upload compensation and unowned-blob cleanup."
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 5,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  @impl true
  def perform(_job) do
    with {:ok, counts} <- AikeStorage.Reconciliation.run(DocumentOcr.BlobOwner.owner()) do
      :telemetry.execute([:aike, :storage, :reconciliation], counts, %{})
      :ok
    end
  end
end
