defmodule BackofficeWeb.AuthController do
  @moduledoc "Thin HTTP actions for bootstrap and human sessions."
  use BackofficeWeb, :controller

  action_fallback(BackofficeWeb.FallbackController)
  alias BackofficeWeb.Schemas.Params
  plug(:authorize_bootstrap when action == :bootstrap)

  plug(BackofficeWeb.ValidateParams,
    bootstrap: &Params.bootstrap/1,
    login: &Params.login/1,
    refresh: &Params.refresh/1,
    password: &Params.password/1
  )

  alias Backoffice.{Accounts, Sessions}
  alias BackofficeWeb.AuthJSON
  alias KycCore.JsonKeyFormatter

  def bootstrap(conn, params) do
    with {:ok, user} <-
           Accounts.bootstrap(%{
             email: params["email"],
             password: params["password"],
             name: params["name"],
             company_name: params["companyName"] || params["company_name"]
           }) do
      conn
      |> put_resp_header("location", "/v1/users/#{user.id}")
      |> put_status(:created)
      |> respond(AuthJSON.user(user))
    end
  end

  def login(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    with {:ok, pair} <- Sessions.login(email, password), do: respond(conn, AuthJSON.session(pair))
  end

  def login(_conn, _), do: {:error, :bad_request}

  def refresh(conn, %{"refreshToken" => token}) when is_binary(token) do
    with {:ok, pair} <- Sessions.refresh(token), do: respond(conn, AuthJSON.session(pair))
  end

  def refresh(_conn, _), do: {:error, :bad_request}

  def me(conn, _), do: respond(conn, AuthJSON.user(conn.assigns.identity.user))

  def logout(conn, _) do
    identity = conn.assigns.identity

    with :ok <- Sessions.logout(identity.session_id, identity.user.id),
         do: respond(conn, AuthJSON.ok())
  end

  def logout_all(conn, _) do
    with {:ok, :ok} <- Sessions.logout_all(conn.assigns.identity.user),
         do: respond(conn, AuthJSON.ok())
  end

  def password(conn, %{"currentPassword" => current, "newPassword" => password})
      when is_binary(current) and is_binary(password) do
    with {:ok, :ok} <- Sessions.change_password(conn.assigns.identity.user, current, password),
         do: respond(conn, AuthJSON.ok())
  end

  def password(_conn, _), do: {:error, :bad_request}

  defp authorize_bootstrap(conn, _) do
    case bootstrap_token(conn) do
      :ok -> conn
      {:error, reason} -> conn |> BackofficeWeb.ResponseHelpers.render_error(reason) |> halt()
    end
  end

  defp bootstrap_token(conn) do
    expected =
      Application.get_env(:backoffice, :bootstrap_token) ||
        Application.get_env(:backoffice, :admin_token)

    with true <- is_binary(expected) and byte_size(expected) >= 32,
         ["Bearer " <> supplied] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(supplied, expected) do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp respond(conn, body), do: json(conn, JsonKeyFormatter.format(body))
end
