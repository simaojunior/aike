defmodule Biometrics.Application do
  @moduledoc """
  OTP application of the biometrics service.

  It starts the repository, the HTTP endpoint, Oban and the completion registry.
  """
  use Application

  def start(_type, _args) do
    children = [
      Biometrics.Repo,
      BiometricsWeb.Endpoint,
      {Oban, Application.fetch_env!(:biometrics, Oban)},
      {Registry, keys: :duplicate, name: Biometrics.Completion.Registry},
      Biometrics.Completion
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Biometrics.Supervisor)
  end
end
