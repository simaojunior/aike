defmodule Biometrics.Facematches.FacematchResult do
  @moduledoc "Persisted facematch domain data."
  use Biometrics, :model
  @type t :: %__MODULE__{}
  @type attrs :: map()
  @type changeset :: Ecto.Changeset.t(t())

  schema "facematch_results" do
    field(:data, :map)
    belongs_to(:session, Biometrics.Facematches.FacematchSession)
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), attrs()) :: changeset()
  def changeset(result, attrs),
    do: cast(result, attrs, [:session_id, :data]) |> validate_required([:session_id, :data])
end
