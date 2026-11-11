defmodule AikeHttp.MixProject do
  use Mix.Project

  def project do
    [
      app: :aike_http,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      deps: [
        {:kyc_core, in_umbrella: true},
        {:plug, "~> 1.18"},
        {:jason, "~> 1.4"},
        {:peri, "~> 0.6.2"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
