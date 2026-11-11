defmodule Backoffice.Auth.Secret do
  @moduledoc """
  Hashes and verifies service account secrets.

  Secrets use PBKDF2-HMAC-SHA256 with a random salt. The plaintext value is never stored.
  """
  @type encoded_hash :: String.t()
  @doc "Hashes a service secret without ever persisting the plaintext value."
  @spec hash(String.t()) :: encoded_hash()
  def hash(secret) when is_binary(secret) do
    salt = :crypto.strong_rand_bytes(16)
    digest = :crypto.pbkdf2_hmac(:sha256, secret, salt, 100_000, 32)

    "pbkdf2-sha256$100000$#{Base.encode64(salt, padding: false)}$#{Base.encode64(digest, padding: false)}"
  end

  @spec valid?(String.t(), encoded_hash()) :: boolean()
  def valid?(secret, encoded_hash) when is_binary(secret) and is_binary(encoded_hash) do
    case String.split(encoded_hash, "$", parts: 4) do
      ["pbkdf2-sha256", iterations, salt, expected] ->
        with {iterations, ""} <- Integer.parse(iterations),
             {:ok, salt} <- Base.decode64(salt, padding: false),
             {:ok, expected} <- Base.decode64(expected, padding: false) do
          actual = :crypto.pbkdf2_hmac(:sha256, secret, salt, iterations, byte_size(expected))
          Plug.Crypto.secure_compare(actual, expected)
        else
          _ -> false
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end
end
