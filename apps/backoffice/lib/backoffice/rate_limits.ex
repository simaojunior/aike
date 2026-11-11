defmodule Backoffice.RateLimits do
  alias Ecto.Adapters.SQL
  @moduledoc "Shared fixed-window authentication limits; keys contain hashes, never emails."
  use Backoffice, :repository
  @spec check(String.t(), pos_integer()) :: :ok | {:error, :rate_limited}
  def check(key, maximum) do
    hash = :crypto.hash(:sha256, key)

    %{rows: [[attempts]]} =
      SQL.query!(
        Repo,
        """
        INSERT INTO backoffice_auth_limits (key, attempts, expires_at)
        VALUES ($1, 1, timezone('UTC', now()) + interval '5 minutes')
        ON CONFLICT (key) DO UPDATE SET
          attempts = CASE WHEN backoffice_auth_limits.expires_at <= timezone('UTC', now())
            THEN 1 ELSE backoffice_auth_limits.attempts + 1 END,
          expires_at = CASE WHEN backoffice_auth_limits.expires_at <= timezone('UTC', now())
            THEN timezone('UTC', now()) + interval '5 minutes' ELSE backoffice_auth_limits.expires_at END
        RETURNING attempts
        """,
        [hash]
      )

    permit(attempts <= maximum)
  end

  defp permit(true), do: :ok
  defp permit(false), do: {:error, :rate_limited}
end
