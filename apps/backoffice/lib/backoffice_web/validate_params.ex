defmodule BackofficeWeb.ValidateParams do
  @moduledoc "Validates HTTP inputs with Peri and halts before domain/persistence on failure."
  import Plug.Conn

  def init(opts), do: Map.new(opts)

  def call(conn, validators) do
    case Map.get(validators, Phoenix.Controller.action_name(conn)) do
      nil -> conn
      validator -> validate(conn, validator)
    end
  end

  defp validate(conn, validator) do
    params = normalize(conn.params)

    case validator.(params) do
      {:ok, params} ->
        %{conn | params: Map.merge(params, conn.path_params)}

      {:error, errors} ->
        conn |> BackofficeWeb.ResponseHelpers.render_validation(errors) |> halt()
    end
  end

  defp normalize(params) do
    params =
      Enum.reduce(
        [
          {"company_name", "companyName"},
          {"company_id", "companyId"},
          {"account_id", "accountId"}
        ],
        params,
        fn {old, new}, acc ->
          if Map.has_key?(acc, old), do: Map.put_new(acc, new, acc[old]), else: acc
        end
      )

    case params do
      %{"email" => email} when is_binary(email) ->
        Map.put(params, "email", email |> String.trim() |> String.downcase())

      _ ->
        params
    end
  end
end
