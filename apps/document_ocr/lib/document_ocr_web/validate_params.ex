defmodule DocumentOcrWeb.ValidateParams do
  @moduledoc "Validates controller payloads with Peri before domain calls."
  import Plug.Conn

  def init(opts), do: Map.new(opts)

  def call(conn, validators) do
    case Map.get(validators, Phoenix.Controller.action_name(conn)) do
      nil -> conn
      validator -> validate(conn, validator)
    end
  end

  defp validate(conn, validator) do
    case validator.(conn.params) do
      {:ok, params} -> %{conn | params: Map.merge(conn.path_params, params)}
      {:error, _errors} -> conn |> put_status(:unprocessable_entity) |> json_error() |> halt()
    end
  end

  defp json_error(conn), do: send_resp(conn, 422, Jason.encode!(%{error: "invalid_request"}))
end
