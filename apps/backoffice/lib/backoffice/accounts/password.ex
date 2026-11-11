defmodule Backoffice.Accounts.Password do
  @moduledoc "Argon2id password hashing with bounded input and a dummy missing-user check."
  @options [argon2_type: 2, m_cost: 15, t_cost: 2, parallelism: 1]
  @spec valid?(term()) :: boolean()
  def valid?(password), do: validation_error(password) == nil

  @doc "Returns public policy metadata only, never the supplied password."
  def validation_error(nil), do: {"is required", [validation: :required]}
  def validation_error(""), do: {"is required", [validation: :required]}

  def validation_error(password) when is_binary(password) do
    cond do
      not String.valid?(password) ->
        {"must be valid UTF-8 text", [validation: :format]}

      byte_size(password) > 1024 ->
        {"must be at most 1024 bytes", [validation: :byte_length]}

      String.length(password) < 15 ->
        {"must be at least %{count} characters", [validation: :length, kind: :min, count: 15]}

      true ->
        nil
    end
  end

  def validation_error(_), do: {"must be a string", [validation: :cast]}

  @spec hash(String.t()) :: String.t()
  def hash(password), do: Argon2.hash_pwd_salt(password, @options)
  @spec verify(term(), term()) :: boolean()
  def verify(password, hash)
      when is_binary(password) and byte_size(password) <= 1024 and is_binary(hash),
      do: Argon2.verify_pass(password, hash)

  def verify(_, _), do: false
  @spec dummy_verify() :: false
  def dummy_verify, do: Argon2.no_user_verify(@options)
end
