defmodule Biometrics.FacematchResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "facematch_results" do
    field(:data, :map)
    belongs_to(:session, Biometrics.FacematchSession)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(result, attrs), do: cast(result, attrs, [:session_id, :data]) |> validate_required([:session_id, :data])
end
