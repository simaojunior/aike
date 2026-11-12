defmodule BackofficeWeb.UserController do
  @moduledoc "Tenant-scoped user administration through the Accounts context."
  use BackofficeWeb, :controller
  action_fallback(BackofficeWeb.FallbackController)
  alias BackofficeWeb.Schemas.Params
  plug(BackofficeWeb.ValidateParams, create: &Params.create_user/1, update: &Params.update_user/1)

  alias Backoffice.Accounts
  alias BackofficeWeb.AuthJSON
  alias KycCore.JsonKeyFormatter

  def index(conn, _) do
    with {:ok, users} <- Accounts.list_users(conn.assigns.identity.user),
         do: json(conn, JsonKeyFormatter.format(AuthJSON.users(users)))
  end

  def create(conn, %{"email" => email, "name" => name, "password" => password} = params)
      when is_binary(email) and is_binary(name) and is_binary(password) do
    attrs = %{
      email: email,
      name: name,
      password: password,
      role: params["role"],
      company_id: params["company_id"]
    }

    with {:ok, user} <- Accounts.create_user(conn.assigns.identity.user, attrs),
         do:
           conn
           |> put_resp_header("location", "/v1/users/#{user.id}")
           |> put_status(:created)
           |> json(JsonKeyFormatter.format(AuthJSON.user(user)))
  end

  def create(_conn, _), do: {:error, :bad_request}

  def update(conn, %{"id" => id} = params) when is_binary(id) do
    attrs =
      for {key, value} <- Map.take(params, ["active", "role"]),
          into: %{},
          do: {attribute(key), value}

    with {:ok, user} <- Accounts.update_user(conn.assigns.identity.user, id, attrs),
         do: json(conn, JsonKeyFormatter.format(AuthJSON.user(user)))
  end

  def update(_conn, _), do: {:error, :bad_request}
  defp attribute("active"), do: :active
  defp attribute("role"), do: :role
end
