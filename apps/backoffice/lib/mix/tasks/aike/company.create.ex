defmodule Mix.Tasks.Aike.Company.Create do
  @moduledoc "Provisions a company through trusted local database access."
  @shortdoc "Creates an Aike tenant company"

  use Mix.Task

  alias Backoffice.Provisioning

  @impl Mix.Task
  def run([name]) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:backoffice)

    case Provisioning.create_company(Backoffice.Repo, %{name: name}) do
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
