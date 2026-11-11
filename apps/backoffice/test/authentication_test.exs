defmodule Backoffice.AuthenticationTest do
  alias Ecto.Adapters.SQL
  use ExUnit.Case, async: false
  alias Backoffice.{Accounts, Repo, Sessions}

  @password "Correct horse battery staple 42!"

  setup do
    :ok = SQL.Sandbox.checkout(Repo)
    SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp bootstrap do
    Accounts.bootstrap(%{
      company_name: "Konoha",
      name: "Platform Admin",
      email: "ADMIN@example.test",
      password: @password
    })
  end

  test "bootstrap is one-time and passwords are never stored in plaintext" do
    assert {:ok, user} = bootstrap()
    assert user.role == :platform_admin
    assert user.email == "admin@example.test"
    assert String.starts_with?(user.password_hash, "$argon2id$")
    refute user.password_hash == @password
    assert {:error, :already_bootstrapped} = bootstrap()
  end

  test "login, immediate logout and stored token hashes" do
    {:ok, user} = bootstrap()
    assert {:ok, pair} = Sessions.login(" ADMIN@example.test ", @password)
    assert {:ok, %{user: authenticated}} = Sessions.authenticate(pair.access_token)
    assert authenticated.id == user.id
    rows = SQL.query!(Repo, "SELECT token_hash FROM backoffice_tokens", []).rows
    refute List.flatten(rows) |> Enum.any?(&(&1 in [pair.access_token, pair.refresh_token]))
    assert :ok = Sessions.logout(pair.session_id, user.id)
    assert {:error, :unauthorized} = Sessions.authenticate(pair.access_token)
    assert {:error, :unauthorized} = Sessions.refresh(pair.refresh_token)
  end

  test "refresh rotates tokens; replay revokes the entire session" do
    {:ok, _} = bootstrap()
    {:ok, first} = Sessions.login("admin@example.test", @password)
    assert {:ok, second} = Sessions.refresh(first.refresh_token)
    refute first.access_token == second.access_token
    refute first.refresh_token == second.refresh_token
    assert {:error, :unauthorized} = Sessions.authenticate(first.access_token)
    assert {:ok, _} = Sessions.authenticate(second.access_token)
    assert {:error, :refresh_token_reused} = Sessions.refresh(first.refresh_token)
    assert {:error, :unauthorized} = Sessions.authenticate(second.access_token)
    assert {:error, :unauthorized} = Sessions.refresh(second.refresh_token)
  end

  test "missing user and incorrect password have the same error" do
    {:ok, _} = bootstrap()
    assert {:error, :invalid_credentials} = Sessions.login("admin@example.test", "wrong-password")

    assert {:error, :invalid_credentials} =
             Sessions.login("missing@example.test", "wrong-password")

    assert {:error, :unauthorized} = Sessions.authenticate("not-a-session-token")
  end

  test "tenant admins cannot grant platform privileges or cross tenant boundaries" do
    {:ok, platform} = bootstrap()
    {:ok, company} = Backoffice.Provisioning.create_company(Repo, %{name: "Customer"})

    {:ok, admin} =
      Accounts.create_user(platform, %{
        company_id: company.id,
        name: "Tenant Admin",
        email: "customer@example.test",
        password: @password,
        role: "company_admin"
      })

    attrs = %{
      company_id: company.id,
      name: "Member",
      email: "member@example.test",
      password: @password
    }

    assert {:error, :forbidden} =
             Accounts.create_user(admin, Map.put(attrs, :role, "platform_admin"))

    assert {:error, :forbidden} =
             Accounts.create_user(admin, %{attrs | company_id: platform.company_id})

    assert {:ok, member} = Accounts.create_user(admin, Map.put(attrs, :role, "company_user"))
    assert member.company_id == company.id
    assert {:error, :forbidden} = Accounts.update_user(admin, platform.id, %{active: false})
    assert {:error, :forbidden} = Accounts.create_user(member, attrs)
  end

  test "expiration, password changes and company deactivation invalidate sessions" do
    {:ok, user} = bootstrap()
    {:ok, expired} = Sessions.login(user.email, @password)
    import Ecto.Query

    Repo.update_all(
      from(t in Backoffice.Sessions.Token, where: t.session_id == ^expired.session_id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
    )

    assert {:error, :unauthorized} = Sessions.authenticate(expired.access_token)
    assert {:error, :unauthorized} = Sessions.refresh(expired.refresh_token)

    {:ok, pair} = Sessions.login(user.email, @password)

    assert {:error, :invalid_credentials} =
             Sessions.change_password(user, "wrong", @password <> "new")

    assert {:ok, _} = Sessions.authenticate(pair.access_token)
    assert {:ok, :ok} = Sessions.change_password(user, @password, @password <> "new")
    assert {:error, :unauthorized} = Sessions.authenticate(pair.access_token)
    assert {:error, :unauthorized} = Sessions.refresh(pair.refresh_token)
    assert {:error, :invalid_credentials} = Sessions.login(user.email, @password)
    {:ok, pair} = Sessions.login(user.email, @password <> "new")

    Repo.update_all(from(c in Backoffice.Tenants.Company, where: c.id == ^user.company_id),
      set: [active: false]
    )

    assert {:error, :unauthorized} = Sessions.authenticate(pair.access_token)
    assert {:error, :unauthorized} = Sessions.refresh(pair.refresh_token)
    assert {:error, :invalid_credentials} = Sessions.login(user.email, @password <> "new")
  end

  test "owner company membership does not grant platform privileges and stale actors cannot authorize" do
    {:ok, platform} = bootstrap()

    {:ok, user} =
      Accounts.create_user(platform, %{
        name: "Company Admin",
        email: "owner-staff@example.test",
        password: @password,
        role: :company_admin
      })

    assert {:error, :forbidden} =
             Backoffice.Administration.create_company(user, %{name: "Denied"})

    assert {:error, :forbidden} =
             Accounts.create_user(user, %{
               name: "Denied",
               email: "denied@example.test",
               password: @password,
               role: :platform_admin
             })

    {:ok, pair} = Sessions.login(user.email, @password)
    assert {:ok, _} = Accounts.update_user(platform, user.id, %{role: :company_user})
    assert {:error, :unauthorized} = Sessions.authenticate(pair.access_token)

    assert {:error, :forbidden} =
             Accounts.create_user(user, %{
               name: "Denied",
               email: "denied@example.test",
               password: @password
             })
  end

  test "disabling a user invalidates existing access and refresh tokens" do
    {:ok, platform} = bootstrap()

    {:ok, user} =
      Accounts.create_user(platform, %{
        company_id: platform.company_id,
        name: "Staff Member",
        email: "staff@example.test",
        password: @password,
        role: "company_user"
      })

    {:ok, pair} = Sessions.login(user.email, @password)
    assert {:ok, _} = Accounts.update_user(platform, user.id, %{active: false})
    assert {:error, :unauthorized} = Sessions.authenticate(pair.access_token)
    assert {:error, :unauthorized} = Sessions.refresh(pair.refresh_token)
    assert {:error, :invalid_credentials} = Sessions.login(user.email, @password)

    assert {:error, :last_platform_admin} =
             Accounts.update_user(platform, platform.id, %{active: false})
  end
end
