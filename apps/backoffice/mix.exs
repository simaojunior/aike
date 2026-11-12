defmodule Backoffice.MixProject do
  use Mix.Project

  def project do
    [
      app: :backoffice,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      deps: [
        {:aike_http, in_umbrella: true},
        {:argon2_elixir, "~> 4.1"},
        {:aike_observability, in_umbrella: true},
        {:kyc_core, in_umbrella: true},
        {:ecto_sql, "~> 3.13"},
        {:postgrex, "~> 0.21"},
        {:phoenix, "~> 1.8.0"},
        {:bandit, "~> 1.6"},
        {:jason, "~> 1.4"},
        {:peri, "~> 0.12.0"}
      ]
    ]
  end

  def application, do: [mod: {Backoffice.Application, []}, extra_applications: [:logger]]
end
