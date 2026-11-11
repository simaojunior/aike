defmodule Backoffice.Administration do
  @moduledoc "Scope-checked provisioning for human administrators."
  alias Backoffice.{Accounts, Audit, Provisioning, Repo, Transaction}
  alias Backoffice.Accounts.UserRepo

  @spec create_company(map(), map()) :: {:ok, map()} | {:error, term()}
  def create_company(actor, attrs) do
    Transaction.run(fn ->
      UserRepo.admin_lock()

      with {:ok, actor} <- Accounts.authorize(actor, "companies.create"),
           {:ok, company} <- Provisioning.create_company(Repo, attrs),
           {:ok, _} <- Audit.record(actor, "company.created", company.id, company.id) do
        {:ok, company}
      end
    end)
  end

  @spec create_service_account(map(), map()) :: {:ok, {map(), String.t()}} | {:error, term()}
  def create_service_account(actor, attrs) do
    Transaction.run(fn ->
      UserRepo.admin_lock()
      company_id = attrs[:company_id] || actor.company_id

      with {:ok, actor} <- Accounts.authorize(actor, "service_accounts.create", company_id),
           {:ok, {account, _secret} = result} <-
             Provisioning.create_service_account(Repo, company_id, attrs),
           {:ok, _} <- Audit.record(actor, "service_account.created", account.id, company_id) do
        {:ok, result}
      end
    end)
  end
end
