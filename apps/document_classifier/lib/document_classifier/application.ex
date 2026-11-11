defmodule DocumentClassifier.Application do
  @moduledoc """
  OTP application of the classifier service.

  It starts the HTTP endpoint. The service keeps no state.
  """
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([DocumentClassifierWeb.Endpoint],
      strategy: :one_for_one,
      name: DocumentClassifier.Supervisor
    )
  end
end
