defmodule AikeAuth.MixProject do
  use Mix.Project

  def project do
    [
      app: :aike_auth,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      deps: [
        {:aike_http, in_umbrella: true},
        {:plug, "~> 1.18"},
        {:jason, "~> 1.4"},
        {:telemetry, "~> 1.0"}
      ]
    ]
  end

  def application,
    do: [mod: {AikeAuth.Application, []}, extra_applications: [:inets, :ssl, :crypto]]
end
