defmodule Backoffice.ServiceIdentity do
  @moduledoc "Validates service credentials against the authoritative administrative database."
  alias Backoffice.{Repo, Auth.Secret, Auth.ServiceAccount, Tenants.Company}

  def authenticate(account_id, secret)
      when is_binary(account_id) and byte_size(account_id) in 1..128 and
             is_binary(secret) and byte_size(secret) in 1..512 do
    with %ServiceAccount{active: true} = account <-
           Repo.get_by(ServiceAccount, account_id: account_id),
         true <- Secret.valid?(secret, account.secret_hash),
         %Company{active: true} <- Repo.get(Company, account.company_id) do
      {:ok,
       %{account_id: account.account_id, company_id: account.company_id, scopes: account.scopes}}
    else
      _ -> {:error, :unauthorized}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def authenticate(_, _), do: {:error, :unauthorized}
end
