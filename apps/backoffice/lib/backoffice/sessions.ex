defmodule Backoffice.Sessions do
  @moduledoc "Password authentication and immediately revocable, rotating opaque credentials."
  alias Backoffice.Accounts.Password
  alias Backoffice.Accounts.User
  alias Backoffice.Accounts.UserRepo
  alias Backoffice.RateLimits
  alias Backoffice.Repo
  alias Backoffice.Sessions.SessionRepo
  alias Backoffice.Transaction

  @spec login(term(), term()) :: {:ok, map()} | {:error, atom()}
  def login(email, password)
      when is_binary(email) and byte_size(email) <= 254 and is_binary(password) and
             byte_size(password) <= 1024 do
    normalized = User.normalize_email(email)

    with :ok <- RateLimits.check("email:" <> normalized, 10),
         {:ok, user} <- verify(UserRepo.by_email(normalized), password) do
      Transaction.run(fn -> create_session(user) end)
    end
  end

  def login(_, _), do: {:error, :invalid_credentials}

  @spec authenticate(term()) ::
          {:ok, %{user: User.t(), session_id: Ecto.UUID.t()}} | {:error, :unauthorized}
  def authenticate(value) when is_binary(value) and byte_size(value) == 43 do
    with {token, session, user} <- SessionRepo.lookup(value, :access),
         true <- valid_session?(session) and fresh?(token) do
      {:ok, %{user: user, session_id: session.id}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def authenticate(_), do: {:error, :unauthorized}

  @spec refresh(term()) :: {:ok, map()} | {:error, atom()}
  def refresh(value) when is_binary(value) and byte_size(value) == 43 do
    found = SessionRepo.lookup(value, :refresh)
    refresh_session(found, value)
  end

  def refresh(_), do: {:error, :unauthorized}

  defp refresh_session(nil, _), do: {:error, :unauthorized}

  defp refresh_session({_token, session, user}, value) do
    # Replay revocation must commit; Transaction.run would roll an error back.
    {:ok, result} =
      Repo.transaction(fn ->
        _ = UserRepo.lock(user.id)
        _ = SessionRepo.lock(session.id)
        rotate(SessionRepo.lookup(value, :refresh))
      end)

    result
  end

  @spec logout(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, :unauthorized}
  def logout(session_id, user_id) do
    result =
      Transaction.run(fn ->
        _ = UserRepo.lock(user_id)

        with %{user_id: ^user_id} = session <- SessionRepo.lock(session_id),
             :ok <- SessionRepo.revoke(session) do
          {:ok, :ok}
        else
          _ -> {:error, :unauthorized}
        end
      end)

    logout_result(result)
  end

  @spec logout_all(User.t()) :: {:ok, :ok} | {:error, atom()}
  def logout_all(user) do
    Transaction.run(fn ->
      _ = UserRepo.lock(user.id)
      {:ok, SessionRepo.revoke_all(user.id)}
    end)
  end

  @spec change_password(User.t(), term(), term()) :: {:ok, :ok} | {:error, term()}
  def change_password(user, current_password, new_password) do
    with true <- Password.valid?(new_password),
         {:ok, current} <- UserRepo.get(user.id),
         {:ok, _} <- verify(current, current_password) do
      Transaction.run(fn -> replace_password(current, new_password) end)
    else
      false -> {:error, :invalid_password}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_session(user) do
    with %User{} = locked <- UserRepo.lock(user.id),
         true <-
           locked.active and locked.password_hash == user.password_hash and
             UserRepo.active_company?(locked.company_id),
         {:ok, session} <- SessionRepo.create(locked) do
      SessionRepo.pair(session)
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  defp replace_password(current, password) do
    locked = UserRepo.lock(current.id)

    with true <- locked.active and locked.password_hash == current.password_hash,
         {:ok, _} <-
           UserRepo.update(Ecto.Changeset.change(locked, password_hash: Password.hash(password))) do
      {:ok, SessionRepo.revoke_all(current.id)}
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  defp verify(nil, _password) do
    Password.dummy_verify()
    {:error, :invalid_credentials}
  end

  defp verify(user, password) do
    verified = Password.verify(password, user.password_hash)
    verify_result(verified and user.active and UserRepo.active_company?(user.company_id), user)
  end

  defp verify_result(true, user), do: {:ok, user}
  defp verify_result(false, _), do: {:error, :invalid_credentials}

  defp rotate(nil), do: {:error, :unauthorized}

  defp rotate({token, session, _user}) do
    cond do
      not valid_session?(session) ->
        {:error, :unauthorized}

      not is_nil(token.used_at) ->
        SessionRepo.revoke(session)
        {:error, :refresh_token_reused}

      not fresh?(token) ->
        {:error, :unauthorized}

      true ->
        :ok = SessionRepo.consume(token)
        SessionRepo.pair(session)
    end
  end

  defp valid_session?(session),
    do: is_nil(session.revoked_at) and DateTime.after?(session.expires_at, DateTime.utc_now())

  defp fresh?(token),
    do: is_nil(token.used_at) and DateTime.after?(token.expires_at, DateTime.utc_now())

  defp logout_result({:ok, :ok}), do: :ok
  defp logout_result(error), do: error
end
