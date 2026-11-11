defmodule Backoffice.Audit do
  @moduledoc "Records security events without tokens or passwords."
  alias Backoffice.Audit.EventRepo

  @spec record(map(), String.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Backoffice.Audit.Event.t()} | {:error, Ecto.Changeset.t()}
  def record(actor, action, target_id, company_id),
    do:
      EventRepo.insert(%{
        actor_id: actor.id,
        company_id: company_id,
        action: action,
        target_id: target_id
      })
end
