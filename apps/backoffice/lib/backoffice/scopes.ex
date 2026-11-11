defmodule Backoffice.Scopes do
  @moduledoc "Server-side role grants, with Oke's one-segment wildcard semantics."
  @profile ~w(profile.read profile.password.change)
  @company ~w(companies.read users.read users.create users.update service_accounts.read service_accounts.create service_accounts.revoke)
  @spec for_role(atom() | String.t()) :: [String.t()]
  def for_role(role) when role in [:platform_admin, "platform_admin"],
    do: @profile ++ @company ++ ["companies.create"]

  def for_role(role) when role in [:company_admin, "company_admin"], do: @profile ++ @company
  def for_role(role) when role in [:company_user, "company_user"], do: @profile
  def for_role(_), do: []

  @spec granted?(String.t(), [String.t()]) :: boolean()
  def granted?(required, grants) when is_binary(required) and is_list(grants) do
    segments = String.split(required, ".")

    Enum.any?(grants, fn grant ->
      parts = String.split(grant, ".")

      length(parts) == length(segments) and
        Enum.all?(Enum.zip(parts, segments), fn {part, required} ->
          part == "*" or part == required
        end)
    end)
  end

  @spec allowed?(Backoffice.Accounts.User.t(), String.t(), Ecto.UUID.t() | nil) :: boolean()
  def allowed?(user, required, company_id \\ nil) do
    user.active and granted?(required, for_role(user.role)) and
      (is_nil(company_id) or user.role == :platform_admin or user.company_id == company_id)
  end
end
