defmodule BackofficeWeb do
  @moduledoc "Shared controller conventions for the backoffice API."
  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
    end
  end

  defmacro __using__(which), do: apply(__MODULE__, which, [])
end
