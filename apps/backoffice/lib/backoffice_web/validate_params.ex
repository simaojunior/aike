defmodule BackofficeWeb.ValidateParams do
  @moduledoc "Validates HTTP inputs with Peri and halts before domain/persistence on failure."
  import Plug.Conn
  alias KycCore.JsonKeyFormatter

  def init(opts), do: Map.new(opts)

  def call(conn, validators) do
    case Map.get(validators, Phoenix.Controller.action_name(conn)) do
      nil -> conn
      validator -> validate(conn, validator)
    end
  end

  defp validate(conn, validator) do
    case validator.(normalize(conn.params)) do
      {:ok, params} ->
        %{conn | params: params |> JsonKeyFormatter.parse() |> Map.merge(conn.path_params)}

      {:error, errors} ->
        conn |> BackofficeWeb.ResponseHelpers.render_validation(errors) |> halt()
    end
  end

  defp normalize(%{"email" => email} = params) when is_binary(email),
    do: Map.put(params, "email", email |> String.trim() |> String.downcase())

  defp normalize(params), do: params
end
