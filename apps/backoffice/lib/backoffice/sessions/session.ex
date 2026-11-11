defmodule Backoffice.Sessions.Session do
  @moduledoc "Revocable human session with an absolute expiration."
  use Backoffice, :model

  @type t :: %__MODULE__{}
  schema "backoffice_sessions" do
    belongs_to(:user, Backoffice.Accounts.User)
    field(:expires_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    timestamps()
  end
end
