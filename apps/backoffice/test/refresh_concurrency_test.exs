defmodule Backoffice.RefreshConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Backoffice.Accounts.Password
  alias Backoffice.Accounts.User
  alias Backoffice.Repo
  alias Backoffice.Sessions
  alias Ecto.Adapters.SQL.Sandbox

  test "simultaneous refreshes serialize and replay revocation commits" do
    Sandbox.unboxed_run(Repo, fn ->
      company = Repo.insert!(%Backoffice.Tenants.Company{name: "Refresh concurrency fixture"})
      email = Ecto.UUID.generate() <> "@example.test"

      user =
        Repo.insert!(%User{
          company_id: company.id,
          name: "Concurrent User",
          email: email,
          role: :company_user,
          password_hash: Password.hash("Concurrent password fixture 42!")
        })

      try do
        {:ok, pair} = Sessions.login(email, "Concurrent password fixture 42!")
        parent = self()

        tasks =
          for _ <- 1..2 do
            Task.async(fn ->
              Sandbox.unboxed_run(Repo, fn ->
                send(parent, {:ready, self()})

                receive do
                  :rotate -> Sessions.refresh(pair.refresh_token)
                end
              end)
            end)
          end

        for _ <- tasks, do: assert_receive({:ready, _}, 5_000)
        Enum.each(tasks, &send(&1.pid, :rotate))
        results = Enum.map(tasks, &Task.await(&1, 5_000))
        assert Enum.count(results, &match?({:ok, _}, &1)) == 1
        assert Enum.count(results, &(&1 == {:error, :refresh_token_reused})) == 1
        {:ok, rotated} = Enum.find(results, &match?({:ok, _}, &1))
        assert {:error, :unauthorized} = Sessions.authenticate(rotated.access_token)
        assert {:error, :unauthorized} = Sessions.refresh(rotated.refresh_token)
      after
        Repo.delete!(user)
        Repo.delete!(company)
        key = :crypto.hash(:sha256, "email:" <> email)
        Repo.delete_all(from(l in "backoffice_auth_limits", where: l.key == ^key))
      end
    end)
  end
end
