defmodule DocumentClassifier.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([DocumentClassifier.Repo, DocumentClassifierWeb.Endpoint],
      strategy: :one_for_one,
      name: DocumentClassifier.Supervisor
    )
  end
end
