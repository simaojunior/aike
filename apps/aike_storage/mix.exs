defmodule AikeStorage.MixProject do
  use Mix.Project

  def project do
    [
      app: :aike_storage,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      deps: [{:ecto, "~> 3.13"}, {:req, "~> 0.5"}, {:plug, "~> 1.18", only: :test}]
    ]
  end

  def application, do: [extra_applications: [:xmerl]]
end
