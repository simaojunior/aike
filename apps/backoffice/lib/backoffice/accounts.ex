defmodule Backoffice.Accounts do
  @moduledoc "Human accounts, explicit tenant authorization and one-time platform bootstrap."
  alias Backoffice.Accounts.Password
  alias Backoffice.Accounts.Policy
  alias Backoffice.Accounts.User
  alias Backoffice.Accounts.UserRepo
  alias Backoffice.Audit
  alias Backoffice.Scopes
  alias Backoffice.Sessions.SessionRepo
  alias Backoffice.Transaction

  @type result :: {:ok, User.t()} | {:error, atom() | Ecto.Changeset.t()}

  @spec bootstrap(map()) :: result()
  def bootstrap(attrs) do
    Transaction.run(fn ->
      :ok = UserRepo.admin_lock()

      with :ok <- bootstrap_available(UserRepo.exists?()),
           {:ok, company} <- UserRepo.platform_company(attrs),
           {:ok, user} <-
             insert_user(Map.merge(attrs, %{company_id: company.id, role: :platform_admin})),
           {:ok, _} <- Audit.record(user, "platform.bootstrapped", user.id, company.id) do
        {:ok, user}
      end
    end)
  end

  @spec authorize(User.t(), String.t(), Ecto.UUID.t() | nil) :: result()
  def authorize(actor, scope, company_id \\ nil) do
    with {:ok, current} <- UserRepo.get(actor.id),
         true <- current.active and UserRepo.active_company?(current.company_id),
         true <- Scopes.allowed?(current, scope, company_id) do
      {:ok, current}
    else
      _ -> {:error, :forbidden}
    end
  end

  @spec create_user(User.t(), map()) :: result()
  def create_user(actor, attrs) do
    Transaction.run(fn ->
      :ok = UserRepo.admin_lock()
      company_id = attrs[:company_id] || actor.company_id

      with {:ok, actor} <- authorize(actor, "users.create", company_id),
           {:ok, role} <- Policy.role(attrs[:role] || :company_user),
           :ok <- Policy.grant(actor, role, company_id),
           {:ok, user} <- insert_user(Map.merge(attrs, %{company_id: company_id, role: role})),
           {:ok, _} <- Audit.record(actor, "user.created", user.id, company_id) do
        {:ok, user}
      end
    end)
  end

  @spec update_user(User.t(), Ecto.UUID.t(), map()) :: result()
  def update_user(actor, id, attrs) do
    Transaction.run(fn ->
      :ok = UserRepo.admin_lock()

      with {:ok, user} <- UserRepo.get(id),
           {:ok, actor} <- authorize(actor, "users.update", user.company_id),
           :ok <- Policy.edit(actor, user),
           {:ok, role} <- Policy.role(Map.get(attrs, :role, user.role)),
           :ok <- Policy.grant(actor, role, user.company_id),
           :ok <- Policy.retain_admin(user, role, Map.get(attrs, :active, user.active)),
           locked = UserRepo.lock(user.id),
           {:ok, updated} <-
             UserRepo.update(User.access_changeset(locked, Map.put(attrs, :role, role))),
           :ok <- SessionRepo.revoke_all(updated.id),
           {:ok, _} <- Audit.record(actor, "user.updated", updated.id, updated.company_id) do
        {:ok, updated}
      end
    end)
  end

  @spec list_users(User.t()) :: {:ok, [User.t()]} | {:error, atom()}
  def list_users(actor) do
    with {:ok, current} <- authorize(actor, "users.read"), do: {:ok, UserRepo.list(current)}
  end

  defp bootstrap_available(false), do: :ok
  defp bootstrap_available(true), do: {:error, :already_bootstrapped}

  defp insert_user(attrs) do
    changeset = User.changeset(%User{}, attrs)

    changeset =
      case Password.validation_error(attrs[:password]) do
        nil -> changeset
        {message, opts} -> Ecto.Changeset.add_error(changeset, :password, message, opts)
      end

    cond do
      not changeset.valid? ->
        {:error, changeset}

      not UserRepo.active_company?(attrs[:company_id]) ->
        {:error,
         Ecto.Changeset.add_error(changeset, :company_id, "must identify an active company",
           validation: :inclusion
         )}

      true ->
        insert_valid_user(changeset, attrs.password)
    end
  end

  defp insert_valid_user(%{valid?: true} = changeset, password) do
    changeset
    |> Ecto.Changeset.put_change(:password_hash, Password.hash(password))
    |> UserRepo.insert()
  end
end
