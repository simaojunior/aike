defmodule Biometrics.Application do
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
