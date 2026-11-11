defmodule Biometrics.Workers.CompareFaces do
  use Oban.Worker, queue: :biometrics, max_attempts: 3

  @impl true
  def perform(%Oban.Job{args: %{"id" => id}} = job),
    do: Biometrics.Facematches.process(id, job.attempt, job.max_attempts, &compare/1)

  defp compare(session) do
    engine = Application.fetch_env!(:biometrics, :engine)
    version = Application.fetch_env!(:biometrics, :engine_version)

    with true <-
           is_nil(session.engine) or
             (session.engine == inspect(engine) and session.engine_version == version),
         {:ok, selfie} <- AikeStorage.Blobs.get(session.selfie_blob),
         {:ok, document} <- AikeStorage.Blobs.get(session.document_blob),
         {:ok, result} <- Biometrics.compare(selfie, document) do
      case Biometrics.Facematches.complete(session, result) do
        {:ok, _} -> :ok
        {:error, _reason} -> {:error, :processing_failed}
      end
    else
      false -> {:error, :engine_version_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end
end
