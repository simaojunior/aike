defmodule Backoffice.Sessions.SessionRepo do
  @moduledoc "Session persistence; callers lock the user before locking sessions."
  use Backoffice, :repository

  alias Backoffice.Accounts.User
  alias Backoffice.Sessions.{Session, Token}
  alias Backoffice.Tenants.Company

  @spec create(User.t()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def create(user),
    do:
      Repo.insert(%Session{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30 * 86_400)
      })

  @spec lock(Ecto.UUID.t()) :: Session.t() | nil
  def lock(id), do: Repo.one(from(s in Session, where: s.id == ^id, lock: "FOR UPDATE"))

  @spec lookup(String.t(), atom()) :: {Token.t(), Session.t(), User.t()} | nil
  def lookup(value, kind) do
    hash = Token.hash(value)

    Repo.one(
      from(t in Token,
        join: s in Session,
        on: s.id == t.session_id,
        join: u in User,
        on: u.id == s.user_id,
        join: c in Company,
        on: c.id == u.company_id,
        where: t.token_hash == ^hash and t.kind == ^kind and u.active and c.active,
        select: {t, s, u}
      )
    )
  end

  @spec pair(Session.t()) :: {:ok, map()}
  def pair(session) do
    now = DateTime.utc_now()
    access = Token.generate()
    refresh = Token.generate()
    access_expiry = earliest(DateTime.add(now, 600), session.expires_at)
    refresh_expiry = earliest(DateTime.add(now, 14 * 86_400), session.expires_at)

    Repo.insert!(%Token{
      token_hash: Token.hash(access),
      session_id: session.id,
      kind: :access,
      expires_at: access_expiry
    })

    Repo.insert!(%Token{
      token_hash: Token.hash(refresh),
      session_id: session.id,
      kind: :refresh,
      expires_at: refresh_expiry
    })

    {:ok,
     %{
       access_token: access,
       refresh_token: refresh,
       session_id: session.id,
       expires_in: DateTime.diff(access_expiry, now, :second),
       token_type: "Bearer"
     }}
  end

  @spec consume(Token.t()) :: :ok
  def consume(token) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(t in Token,
        where:
          t.token_hash == ^token.token_hash or
            (t.session_id == ^token.session_id and t.kind == :access and is_nil(t.used_at))
      ),
      set: [used_at: now]
    )

    :ok
  end

  @spec revoke(Session.t()) :: :ok
  def revoke(session) do
    Repo.update_all(from(s in Session, where: s.id == ^session.id),
      set: [revoked_at: DateTime.utc_now()]
    )

    :ok
  end

  @spec revoke_all(Ecto.UUID.t()) :: :ok
  def revoke_all(user_id) do
    Repo.update_all(from(s in Session, where: s.user_id == ^user_id and is_nil(s.revoked_at)),
      set: [revoked_at: DateTime.utc_now()]
    )

    :ok
  end

  defp earliest(first, second) do
    comparison = DateTime.compare(first, second)
    choose_expiry(comparison, first, second)
  end

  defp choose_expiry(:lt, first, _), do: first
  defp choose_expiry(_, _, second), do: second
end
