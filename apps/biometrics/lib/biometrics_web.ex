defmodule BiometricsWeb do
  @moduledoc "Web entrypoint for the biometrics service."

  @doc "Returns the common controller quoted configuration."
  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
    end
  end

  @doc "Returns the router quoted configuration."
  def router do
    quote do
      use Phoenix.Router
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
