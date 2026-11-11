defmodule BackofficeWeb.AuthJSON do
  @moduledoc "Credential and human identity responses with explicit safe fields."
  @spec user(map()) :: map()
  def user(user),
    do: %{
      id: user.id,
      company_id: user.company_id,
      name: user.name,
      email: user.email,
      role: user.role,
      active: user.active,
      scopes: Backoffice.Scopes.for_role(user.role)
    }

  @spec session(map()) :: map()
  def session(pair), do: Map.take(pair, [:access_token, :refresh_token, :expires_in, :token_type])

  @spec users([map()]) :: map()
  def users(users), do: %{data: Enum.map(users, &user/1)}

  @spec ok() :: %{ok: true}
  def ok, do: %{ok: true}
end
