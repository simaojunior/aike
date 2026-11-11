defmodule AikeObservability.MetricsTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  setup do
    original = Application.fetch_env(:aike_observability, :metrics_token)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:aike_observability, :metrics_token, value)
        :error -> Application.delete_env(:aike_observability, :metrics_token)
      end
    end)

    :ok
  end

  test "Prometheus snapshots include retries, zeroes and no sensitive labels" do
    text =
      AikeObservability.Queues.encode("ocr", ["ocr", "preprocess"], [
        ["ocr", "available", 2, 8.5],
        ["ocr", "retryable", 3, 20.0],
        ["ocr", "completed", 10, 30.0]
      ])

    assert text =~ ~s(aike_queue_jobs{service="ocr",queue="ocr",state="retryable"} 3)
    assert text =~ ~s(aike_queue_jobs{service="ocr",queue="preprocess",state="executing"} 0)
    assert text =~ ~s(aike_queue_oldest_ready_age_seconds{service="ocr",queue="ocr"} 20.0)
    refute text =~ "company_id"
    assert text =~ "# TYPE aike_queue_jobs gauge"
  end

  test "scrape authentication is mandatory and unavailable by default" do
    opts = [app: :aike_observability, repo: UnavailableRepo, queues: ["ocr"]]
    Application.delete_env(:aike_observability, :metrics_token)
    assert AikeObservability.Plug.call(conn(:get, "/metrics"), opts).status == 404
    Application.put_env(:aike_observability, :metrics_token, "private-token")
    assert AikeObservability.Plug.call(conn(:get, "/metrics"), opts).status == 401
    wrong = conn(:get, "/metrics") |> put_req_header("authorization", "Bearer wrong")
    assert AikeObservability.Plug.call(wrong, opts).status == 401
    authorized = conn(:get, "/metrics") |> put_req_header("authorization", "Bearer private-token")
    response = AikeObservability.Plug.call(authorized, opts)
    assert response.status == 503
    assert response.resp_body == "metrics_unavailable\n"
    other = conn(:get, "/v1/extractions")
    assert AikeObservability.Plug.call(other, opts) == other
  end
end
