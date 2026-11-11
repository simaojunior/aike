defmodule Backoffice.Application do
  @moduledoc "Starts only the backoffice repository and HTTP endpoint."
  use Application

  def start(_type, _args) do
    Supervisor.start_link([Backoffice.Repo, BackofficeWeb.Endpoint],
      strategy: :one_for_one,
      name: Backoffice.Supervisor
    )
  end
end
