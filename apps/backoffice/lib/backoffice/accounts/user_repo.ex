defmodule Backoffice.Accounts.UserRepo do
  alias Ecto.Adapters.SQL
  @moduledoc "Persistence and locking for human identities."
  use Backoffice, :repository

  alias Backoffice.Accounts.User
  alias Backoffice.Tenants.Company

  @spec admin_lock() :: :ok
  def admin_lock do
    # Shared by bootstrap and privilege mutations to preserve the last-admin invariant.
    _ = SQL.query!(Repo, "SELECT pg_advisory_xact_lock(424201)", [])
    :ok
  end

  @spec exists?() :: boolean()
  def exists?, do: Repo.exists?(User)

  @spec get(term()) :: {:ok, User.t()} | {:error, :not_found}
  def get(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %User{} = user <- Repo.get(User, uuid) do
      {:ok, user}
    else
      _ -> {:error, :not_found}
    end
  end

  @spec lock(Ecto.UUID.t()) :: User.t() | nil
  def lock(id), do: Repo.one(from(u in User, where: u.id == ^id, lock: "FOR UPDATE"))

  @spec by_email(String.t()) :: User.t() | nil
  def by_email(email), do: Repo.get_by(User, email: email)

  @spec active_company?(term()) :: boolean()
  def active_company?(id) do
    parsed = Ecto.UUID.cast(id)

    case parsed do
      {:ok, uuid} -> Repo.exists?(from(c in Company, where: c.id == ^uuid and c.active))
      _ -> false
    end
  end

  @spec platform_company?(term()) :: boolean()
  def platform_company?(id) do
    parsed = Ecto.UUID.cast(id)

    case parsed do
      {:ok, uuid} ->
        Repo.exists?(from(c in Company, where: c.id == ^uuid and c.active and c.is_platform))

      _ ->
        false
    end
  end

  @spec platform_company(map()) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def platform_company(attrs) do
    existing = Repo.one(from(c in Company, where: c.is_platform))
    ensure_platform_company(existing, attrs)
  end

  defp ensure_platform_company(nil, attrs) do
    %Company{}
    |> Company.changeset(%{name: attrs[:company_name]})
    |> Ecto.Changeset.put_change(:is_platform, true)
    |> Repo.insert()
    |> company_validation_result()
  end

  defp ensure_platform_company(company, _attrs), do: {:ok, company}

  # This context accepts company_name, not the administrator's name.
  defp company_validation_result({:error, %Ecto.Changeset{} = changeset}) do
    errors =
      Enum.map(changeset.errors, fn
        {:name, error} -> {:company_name, error}
        other -> other
      end)

    {:error, %{changeset | errors: errors}}
  end

  defp company_validation_result(result), do: result

  @spec insert(Ecto.Changeset.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def insert(changeset), do: Repo.insert(changeset)

  @spec update(Ecto.Changeset.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update(changeset), do: Repo.update(changeset)

  @spec admin_count() :: non_neg_integer()
  def admin_count,
    do: Repo.aggregate(from(u in User, where: u.active and u.role == :platform_admin), :count)

  @spec list(User.t()) :: [User.t()]
  def list(%{role: :platform_admin}), do: Repo.all(from(u in User, order_by: u.id, limit: 100))

  def list(user),
    do:
      Repo.all(
        from(u in User, where: u.company_id == ^user.company_id, order_by: u.id, limit: 100)
      )
end
