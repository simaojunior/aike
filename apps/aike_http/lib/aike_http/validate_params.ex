defmodule AikeHttp.ValidateParams do
  @moduledoc """
  Runs a Peri schema before any controller domain call.

  Schemas declare the public, camelCase field names, so field errors name what the client
  sent. After validation the parameters are parsed to snake_case
  (`KycCore.JsonKeyFormatter.parse/1`): controllers and contexts only see snake_case.
  Unknown fields, including snake_case names, are dropped by the schema.
  """
  import Plug.Conn
  alias KycCore.JsonKeyFormatter
  def init(opts), do: Map.new(opts)

  def call(conn, validators) do
    case Map.get(validators, conn.private[:phoenix_action]) do
      nil ->
        conn

      validator ->
        result = with {:ok, _} <- validate_headers(conn), do: validator.(conn.params)

        case result do
          {:ok, params} ->
            %{conn | params: params |> JsonKeyFormatter.parse() |> Map.merge(conn.path_params)}

          {:error, errors} ->
            conn |> AikeHttp.Problem.validation(errors) |> halt()
        end
    end
  end

  defp validate_headers(conn) do
    value =
      case get_req_header(conn, "idempotency-key") do
        [] -> nil
        [key] -> key
        keys -> keys
      end

    Peri.validate(%{"idempotency-key" => {:custom, {AikeHttp.Input, :idempotency_key}}}, %{
      "idempotency-key" => value
    })
  end
end
