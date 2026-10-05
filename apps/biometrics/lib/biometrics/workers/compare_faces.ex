defmodule Biometrics.Workers.CompareFaces do
  use Oban.Worker, queue: :biometrics, max_attempts: 3

  @impl true
  def perform(%Oban.Job{args: %{"id" => id}}) do
    session = Biometrics.Facematches.get(id)

    with %{} = session <- session,
         {:ok, selfie} <- AikeStorage.Blobs.get(session.selfie_blob),
         {:ok, document} <- AikeStorage.Blobs.get(session.document_blob),
         {:ok, result} <- Biometrics.compare(selfie, document) do
      case Biometrics.Facematches.complete(session, result) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      nil -> {:cancel, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
