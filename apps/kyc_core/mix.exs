defmodule KycCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :kyc_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      deps: []
    ]
  end

  def application, do: [extra_applications: [:crypto]]
end
