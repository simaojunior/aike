defmodule Backoffice.Sessions.Token do
  @moduledoc "Hashed access or refresh credential; consumed refresh tokens detect replay."
  use Backoffice, :model

  @primary_key {:token_hash, :binary, autogenerate: false}
  @kinds [:access, :refresh]

  @type t :: %__MODULE__{}
  schema "backoffice_tokens" do
    belongs_to(:session, Backoffice.Sessions.Session)
    field(:kind, Ecto.Enum, values: @kinds)
    field(:expires_at, :utc_datetime_usec)
    field(:used_at, :utc_datetime_usec)
  end

  @spec hash(binary()) :: binary()
  def hash(value), do: :crypto.hash(:sha256, value)

  @spec generate() :: String.t()
  def generate, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end
