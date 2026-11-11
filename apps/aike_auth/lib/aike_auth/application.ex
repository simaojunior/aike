defmodule AikeAuth.Application do
  @moduledoc """
  Starts the service identity cache (`AikeAuth.Cache`).
  """
  use Application

  @impl true
  def start(_type, _args),
    do: Supervisor.start_link([AikeAuth.Cache], strategy: :one_for_one, name: AikeAuth.Supervisor)
end
