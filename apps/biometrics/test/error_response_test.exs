defmodule Biometrics.ErrorResponseTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  setup_all do
    # Also runs with --no-start, without starting a Repo or Oban.
    {:ok, _} = Application.ensure_all_started(:phoenix)
    {:ok, _} = Application.ensure_all_started(:bandit)

    unless Process.whereis(BiometricsWeb.Endpoint) do
      start_supervised!(BiometricsWeb.Endpoint)
    end

    :ok
  end

  setup do
    keys = [:service_token, :auth_required, :service_account_auth_required]
    original = Map.new(keys, &{&1, Application.fetch_env(:biometrics, &1)})
    Application.delete_env(:biometrics, :service_token)
    Application.put_env(:biometrics, :auth_required, false)
    Application.put_env(:biometrics, :service_account_auth_required, false)

    on_exit(fn ->
      for {key, value} <- original do
        case value do
          {:ok, value} -> Application.put_env(:biometrics, key, value)
          :error -> Application.delete_env(:biometrics, key)
        end
      end
    end)

    :ok
  end

  for accept <- [nil, "application/json", "text/html"] do
    @accept accept
    test "unknown route returns JSON with accept=#{inspect(accept)}" do
      request = conn(:post, "/v1/service-accounts")
      request = if @accept, do: put_req_header(request, "accept", @accept), else: request
      response = BiometricsWeb.Endpoint.call(request, [])

      assert response.status == 404

      assert get_resp_header(response, "content-type") == [
               "application/problem+json; charset=utf-8"
             ]

      [request_id] = get_resp_header(response, "x-request-id")

      assert Jason.decode!(response.resp_body) == %{
               "id" => request_id,
               "code" => "not_found",
               "detail" => "The requested resource was not found."
             }
    end
  end
end
