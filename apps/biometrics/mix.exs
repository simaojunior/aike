defmodule Biometrics.MixProject do
  use Mix.Project

  def project do
    [
      app: :biometrics,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      deps: [
        {:aike_storage, in_umbrella: true},
        {:kyc_core, in_umbrella: true},
        {:phoenix, "~> 1.8.0"},
        {:bandit, "~> 1.6"},
        {:jason, "~> 1.4"},
        {:ecto_sql, "~> 3.13"},
        {:postgrex, "~> 0.21"},
        {:oban, "~> 2.19"},
        {:peri, "~> 0.6.2"}
      ]
    ]
  end

  def application, do: [mod: {Biometrics.Application, []}, extra_applications: [:logger]]
end
