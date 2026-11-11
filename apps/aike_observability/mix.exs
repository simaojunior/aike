defmodule AikeObservability.MixProject do
  use Mix.Project

  def project do
    [
      app: :aike_observability,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      deps: [{:plug, "~> 1.18"}]
    ]
  end
end
