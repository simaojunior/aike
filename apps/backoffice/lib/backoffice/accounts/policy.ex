defmodule Backoffice.Accounts.Policy do
  @moduledoc "Role assignment and last-administrator invariants."
  alias Backoffice.Accounts.UserRepo

  @spec role(term()) ::
          {:ok, :platform_admin | :company_admin | :company_user} | {:error, :invalid_request}
  def role(value) when value in [:platform_admin, "platform_admin"], do: {:ok, :platform_admin}
  def role(value) when value in [:company_admin, "company_admin"], do: {:ok, :company_admin}
  def role(value) when value in [:company_user, "company_user"], do: {:ok, :company_user}
  def role(_), do: {:error, :invalid_request}

  @spec grant(map(), atom(), Ecto.UUID.t()) :: :ok | {:error, :forbidden}
  def grant(%{role: :platform_admin}, :platform_admin, company_id),
    do: permit(UserRepo.platform_company?(company_id))

  def grant(_, :platform_admin, _), do: {:error, :forbidden}
  def grant(_, _, _), do: :ok

  @spec edit(map(), map()) :: :ok | {:error, :forbidden}
  def edit(%{role: :platform_admin}, _), do: :ok
  def edit(_, %{role: :platform_admin}), do: {:error, :forbidden}
  def edit(_, _), do: :ok

  @spec retain_admin(map(), atom(), term()) :: :ok | {:error, :last_platform_admin}
  def retain_admin(%{role: :platform_admin, active: true}, role, active)
      when role != :platform_admin or active == false do
    retain_count(UserRepo.admin_count())
  end

  def retain_admin(_, _, _), do: :ok
  defp retain_count(count) when count > 1, do: :ok
  defp retain_count(_), do: {:error, :last_platform_admin}
  defp permit(true), do: :ok
  defp permit(false), do: {:error, :forbidden}
end
