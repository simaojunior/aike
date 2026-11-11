defmodule Backoffice.Audit.EventRepo do
  @moduledoc "Persistence for security events."
  use Backoffice, :repository

  alias Backoffice.Audit.Event

  @spec insert(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs), do: Repo.insert(struct!(Event, attrs))
end
