defmodule Backoffice.Audit.Event do
  @moduledoc "Immutable security event metadata without credentials."
  use Backoffice, :model

  @type t :: %__MODULE__{}
  schema "backoffice_audit_events" do
    field(:actor_id, :binary_id)
    field(:company_id, :binary_id)
    field(:action, :string)
    field(:target_id, :binary_id)
    timestamps(updated_at: false)
  end
end
