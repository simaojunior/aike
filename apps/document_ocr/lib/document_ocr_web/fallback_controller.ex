defmodule DocumentOcrWeb.FallbackController do
  @moduledoc "Maps processing failures to the existing HTTP error contract."
  use DocumentOcrWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{}}), do: call(conn, {:error, :invalid_request})
  def call(conn, {:error, _step, _reason, _changes}), do: call(conn, {:error, :invalid_request})

  def call(conn, {:error, reason}) when is_atom(reason) do
    {status, code} = KycCore.HttpErrors.info(reason)
    AikeHttp.Problem.send(conn, status, code)
  end
end
