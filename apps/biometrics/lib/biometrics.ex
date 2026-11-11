defmodule Biometrics do
  @moduledoc "Shared model and repository conventions for biometrics."
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
      alias Biometrics.Repo
    end
  end

  @spec compare(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def compare(selfie, document, opts \\ []) do
    Application.fetch_env!(:biometrics, :engine).compare(selfie, document, opts)
  end
end
