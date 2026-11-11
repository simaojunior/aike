defmodule DocumentOcr.QueueMetricsTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test
  alias DocumentOcr.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    original = Application.fetch_env(:document_ocr, :metrics_token)
    Application.put_env(:document_ocr, :metrics_token, "scrape-secret")

    on_exit(fn ->
      case original do
        {:ok, token} -> Application.put_env(:document_ocr, :metrics_token, token)
        :error -> Application.delete_env(:document_ocr, :metrics_token)
      end
    end)

    :ok
  end

  test "authenticated scrape reports actual queue states and wait age" do
    for state <- ["available", "retryable", "executing", "scheduled"] do
      Repo.insert!(%Oban.Job{
        worker: "DocumentOcr.Workers.OcrDocument",
        queue: "ocr",
        state: state,
        args: %{"private_document" => "not-a-label"},
        scheduled_at: DateTime.add(DateTime.utc_now(), -30, :second)
      })
    end

    response =
      conn(:get, "/metrics")
      |> put_req_header("authorization", "Bearer scrape-secret")
      |> DocumentOcrWeb.Endpoint.call([])

    assert response.status == 200

    assert get_resp_header(response, "content-type") ==
             ["text/plain; version=0.0.4; charset=utf-8"]

    assert response.halted

    assert response.resp_body =~
             ~s(aike_queue_jobs{service="document_ocr",queue="ocr",state="retryable"} 1)

    assert response.resp_body =~
             ~s(aike_queue_jobs{service="document_ocr",queue="ocr",state="available"} 1)

    assert response.resp_body =~
             ~s(aike_queue_jobs{service="document_ocr",queue="preprocess",state="available"} 0)

    refute response.resp_body =~ "not-a-label"
    assert DocumentOcr.Telemetry.queue_depth("ocr") == 4

    [_, age] =
      Regex.run(
        ~r/aike_queue_oldest_ready_age_seconds\{service="document_ocr",queue="ocr"\} ([0-9.]+)/,
        response.resp_body
      )

    assert String.to_float(age) >= 29.0
  end
end
