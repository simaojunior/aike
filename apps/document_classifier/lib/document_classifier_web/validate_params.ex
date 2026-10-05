defmodule DocumentClassifierWeb.ValidateParams do
  @moduledoc "Validates classifier payloads with Peri."
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
      {:ok, params} ->
        %{conn | params: params}

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> send_resp(422, Jason.encode!(%{error: "invalid_request"}))
        |> halt()
    end
  end
end
