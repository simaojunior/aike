defmodule Mix.Tasks.Aike.Company.Create do
  @shortdoc "Creates an Aike tenant company"

  use Mix.Task

  alias KycCore.Auth.Provisioning

  @impl Mix.Task
  def run([company_id, name]) do
    Mix.Task.run("app.start")

    case Provisioning.create_company(DocumentOcr.Repo, %{id: company_id, name: name}) do
      {:ok, company} ->
        Mix.shell().info("Created company #{company.id} (#{company.name})")

      {:error, changeset} ->
        Mix.raise("Could not create company: #{inspect(changeset.errors)}")
    end
  end

  def run(_args) do
    Mix.raise("usage: mix aike.company.create COMPANY_ID NAME")
  end
end
