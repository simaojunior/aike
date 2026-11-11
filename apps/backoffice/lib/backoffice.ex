defmodule Backoffice do
  @moduledoc "Shared model and repository conventions for backoffice domains."

  @doc false
  defmacro __using__(which), do: apply(__MODULE__, which, [])

  @spec model() :: Macro.t()
  def model do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end

  @spec repository() :: Macro.t()
  def repository do
    quote do
      import Ecto.Query
      alias Backoffice.Repo
    end
  end
end
