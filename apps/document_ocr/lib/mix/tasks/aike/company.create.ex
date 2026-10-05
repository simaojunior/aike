defmodule Mix.Tasks.Aike.Company.Create do
  @shortdoc "Creates an Aike tenant company"

  use Mix.Task

  alias KycCore.Auth.Provisioning

  @impl Mix.Task
  def run([name]) do
    Mix.Task.run("app.start")

    case Provisioning.create_company(DocumentOcr.Repo, %{name: name}) do
      {:ok, company} ->
        Mix.shell().info("Created company #{company.id} (#{company.name})")

      {:error, changeset} ->
        Mix.raise("Could not create company: #{inspect(changeset.errors)}")
    end
  end

  def run(_args) do
    Mix.raise("usage: mix aike.company.create NAME")
  end
end
