defmodule AikeVision.MixProject do
  use Mix.Project

  def project do
    [
      app: :aike_vision,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      deps: [{:evision, "~> 1.0"}, {:telemetry, "~> 1.0"}]
    ]
  end

  def application, do: [mod: {AikeVision.Application, []}, extra_applications: [:logger]]
end
