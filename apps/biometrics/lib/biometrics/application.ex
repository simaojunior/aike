defmodule Biometrics.Application do
  use Application

  def start(_type, _args) do
    children = [Biometrics.Repo, BiometricsWeb.Endpoint, {Oban, Application.fetch_env!(:biometrics, Oban)}]
    Supervisor.start_link(children, strategy: :one_for_one, name: Biometrics.Supervisor)
  end
end
