# mix run --no-start scripts/check_boundaries.exs (no database required).
defmodule Aike.CheckBoundaries do
  def dependencies(app, seen \\ MapSet.new()) do
    if MapSet.member?(seen, app) do
      seen
    else
      case Application.load(app) do
        :ok -> :ok
        {:error, {:already_loaded, ^app}} -> :ok
      end

      optional = Application.spec(app, :optional_applications) || []

      available =
        Enum.filter(Application.spec(app, :applications) || [], fn dependency ->
          dependency not in optional or
            :code.where_is_file(String.to_charlist("#{dependency}.app")) != :non_existing
        end)

      Enum.reduce(available, MapSet.put(seen, app), &dependencies/2)
    end
  end
end

for {app, forbidden} <- [
      kyc_core: [:ecto, :ecto_sql, :plug, :phoenix, :oban, :backoffice, :aike_auth, :aike_http],
      document_classifier: [
        :ecto_sql,
        :postgrex,
        :oban,
        :document_ocr,
        :biometrics,
        :backoffice
      ],
      document_ocr: [:backoffice, :biometrics, :document_classifier],
      biometrics: [:document_ocr, :backoffice, :document_classifier],
      backoffice: [:document_ocr, :biometrics, :document_classifier, :oban]
    ] do
  dependencies = Aike.CheckBoundaries.dependencies(app)

  for dependency <- forbidden do
    if MapSet.member?(dependencies, dependency), do: raise("#{app} depends on #{dependency}")
  end
end

[Backoffice.Repo] = Application.fetch_env!(:backoffice, :ecto_repos)
[DocumentOcr.Repo] = Application.fetch_env!(:document_ocr, :ecto_repos)
[Biometrics.Repo] = Application.fetch_env!(:biometrics, :ecto_repos)
[] = Application.get_env(:document_classifier, :ecto_repos, [])
IO.puts("Application dependencies and migration ownership verified")
