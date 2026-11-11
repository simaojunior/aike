# Run with the owner's release eval. Never run migrations from a consumer release.
{app, repo} =
  case System.fetch_env!("RELEASE_NAME") do
    "document_ocr" -> {:document_ocr, DocumentOcr.Repo}
    "backoffice" -> {:backoffice, Backoffice.Repo}
    "biometrics" -> {:biometrics, Biometrics.Repo}
    _ -> raise "Only document_ocr, biometrics and backoffice own migrations"
  end

case Application.load(app) do
  :ok -> :ok
  {:error, {:already_loaded, ^app}} -> :ok
end

{:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
IO.puts("#{app}: migrations applied")
