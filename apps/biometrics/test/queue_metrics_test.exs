defmodule Biometrics.QueueMetricsTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  test "biometrics exposes only its own queues with its operational token" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Biometrics.Repo)
    original = Application.fetch_env(:biometrics, :metrics_token)
    Application.put_env(:biometrics, :metrics_token, "biometrics-scrape")

    on_exit(fn ->
      case original do
        {:ok, token} -> Application.put_env(:biometrics, :metrics_token, token)
        :error -> Application.delete_env(:biometrics, :metrics_token)
      end
    end)

    assert conn(:get, "/metrics") |> BiometricsWeb.Endpoint.call([]) |> Map.fetch!(:status) == 401

    response =
      conn(:get, "/metrics")
      |> put_req_header("authorization", "Bearer biometrics-scrape")
      |> BiometricsWeb.Endpoint.call([])

    assert response.status == 200
    assert response.resp_body =~ ~s(service="biometrics",queue="biometrics")
    refute response.resp_body =~ ~s(queue="ocr")

    wrong_method =
      conn(:post, "/metrics")
      |> put_req_header("authorization", "Bearer biometrics-scrape")
      |> BiometricsWeb.Endpoint.call([])

    assert wrong_method.status == 405
    assert get_resp_header(wrong_method, "allow") == ["GET"]
  end
end
