defmodule Mix.Tasks.Aike.ServiceAccount.Create do
  @moduledoc "Issues a service credential through trusted local database access."
  @shortdoc "Creates an Aike Service Account and prints its secret once"

  use Mix.Task

  alias Backoffice.Provisioning

  @impl Mix.Task
  def run([company_id, name, scopes | optional_account_id]) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:backoffice)

    attrs = %{
      name: name,
      scopes: parse_scopes(scopes)
    }

    attrs = put_account_id(attrs, optional_account_id)

    case Provisioning.create_service_account(Backoffice.Repo, company_id, attrs) do
      {:ok, {account, secret}} ->
        Mix.shell().info("account_id: #{account.account_id}")
        Mix.shell().info("company_id: #{account.company_id}")
        Mix.shell().info("scopes: #{Enum.join(account.scopes, ",")}")
        Mix.shell().info("secret (save now; it cannot be recovered): #{secret}")

      {:error, :company_not_found} ->
        Mix.raise("Company not found: #{company_id}")

      {:error, changeset} ->
        Mix.raise("Could not create service account: #{inspect(changeset.errors)}")
    end
  end

  def run(_args) do
    Mix.raise(
      "usage: mix aike.service_account.create COMPANY_ID NAME SCOPES [ACCOUNT_ID]\n" <>
        "SCOPES is comma-separated, for example ocr:write,ocr:read"
    )
  end

  defp parse_scopes(scopes), do: String.split(scopes, ",", trim: true)

  defp put_account_id(attrs, []), do: attrs
  defp put_account_id(attrs, [account_id]), do: Map.put(attrs, :account_id, account_id)
  defp put_account_id(_attrs, _args), do: Mix.raise("only one optional ACCOUNT_ID is allowed")
end
