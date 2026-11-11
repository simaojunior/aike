defmodule BackofficeWeb.FallbackController do
  @moduledoc "Translates domain failures through the documented HTTP contract."
  use BackofficeWeb, :controller
  alias BackofficeWeb.ResponseHelpers

  def call(conn, {:error, %Ecto.Changeset{} = changeset}),
    do: ResponseHelpers.render_validation(conn, changeset)

  def call(conn, {:error, reason}) when is_atom(reason),
    do: ResponseHelpers.render_error(conn, reason)
end
