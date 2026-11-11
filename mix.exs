defmodule Aike.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: [
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 1.4", only: :dev, runtime: false},
        {:peri, "~> 0.6.2"}
      ],
      aliases: [
        quality: [
          "format --check-formatted",
          "compile --warnings-as-errors",
          "credo --strict",
          "dialyzer"
        ]
      ],
      dialyzer: [
        ignore_warnings: "dialyzer.ignore-warnings",
        plt_add_apps: [:mix],
        flags: [:error_handling, :unmatched_returns, :underspecs]
      ],
      releases: [
        document_ocr: [applications: [document_ocr: :permanent]],
        document_classifier: [applications: [document_classifier: :permanent]],
        biometrics: [applications: [biometrics: :permanent]],
        backoffice: [applications: [backoffice: :permanent]]
      ]
    ]
  end
end
