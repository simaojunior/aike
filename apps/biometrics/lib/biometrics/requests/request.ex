defmodule Biometrics.Requests.Request do
  @moduledoc "An idempotency key bound to one tenant, request fingerprint and resource."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}
  schema "processing_requests" do
    field(:service, Ecto.Enum, values: [:facematch])
    field(:company_id, :string)
    field(:key, :string)
    field(:fingerprint, :string)
    field(:facematch_session_id, :binary_id)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
