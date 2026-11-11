defmodule DocumentOcr.WaitAndWebhooksTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: DocumentOcr.Repo
  import Plug.Test
  import Plug.Conn
  alias DocumentOcr.{Documents, Repo, Webhooks}
  alias DocumentOcr.Webhooks.{Delivery, Target}
  alias DocumentOcr.Workers.DeliverWebhook
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    keys = [
      :max_waiting_requests,
      :webhook_req_options,
      :webhook_require_https,
      :webhook_allow_private_targets
    ]

    original = Map.new(keys, &{&1, Application.get_env(:document_ocr, &1)})

    on_exit(fn ->
      for {key, value} <- original, do: Application.put_env(:document_ocr, key, value)
    end)

    :ok
  end

  defp request(method, path, body \\ nil, headers \\ []) do
    conn = conn(method, path, if(body, do: Jason.encode!(body), else: nil))

    headers
    |> Enum.reduce(put_req_header(conn, "content-type", "application/json"), fn {key, value},
                                                                                conn ->
      put_req_header(conn, key, value)
    end)
    |> DocumentOcrWeb.Endpoint.call([])
  end

  defp payload(external_id \\ "naruto-1") do
    %{
      "appId" => "konoha",
      "externalId" => external_id,
      "document" => %{"type" => "cnh", "country" => "BR"},
      "images" => [%{"side" => "front", "image" => Base.encode64("front-#{external_id}.jpg")}]
    }
  end

  defp drain do
    Oban.drain_queue(queue: :preprocess)
    Oban.drain_queue(queue: :ocr)
    Oban.drain_queue(queue: :default, with_recursion: true)
  end

  defp created_document(external_id) do
    Stream.repeatedly(fn ->
      Process.sleep(20)
      Repo.get_by(Documents.Document, external_id: external_id)
    end)
    |> Enum.find(& &1)
  end

  describe "Prefer: wait" do
    test "answers 200 with the finished extraction when it completes within the wait" do
      task =
        Task.async(fn -> request(:post, "/v1/extractions", payload(), [{"prefer", "wait=5"}]) end)

      created_document("naruto-1")
      drain()
      response = Task.await(task, 10_000)

      assert response.status == 200
      assert get_resp_header(response, "preference-applied") == ["wait=5"]
      body = Jason.decode!(response.resp_body)
      assert body["status"] == "completed"
      assert hd(body["data"])["person"]["name"]["value"] == "NARUTO UZUMAKI"
    end

    test "answers 202 with Location when the wait ends first" do
      response = request(:post, "/v1/extractions", payload(), [{"prefer", "wait=1"}])
      assert response.status == 202
      assert get_resp_header(response, "preference-applied") == ["wait=1"]
      [location] = get_resp_header(response, "location")
      assert location == "/v1/extractions/" <> Jason.decode!(response.resp_body)["id"]
    end

    test "without the header, or with too many waiting requests, answers 202 at once" do
      response = request(:post, "/v1/extractions", payload("naruto-2"))
      assert response.status == 202
      assert get_resp_header(response, "preference-applied") == []

      Application.put_env(:document_ocr, :max_waiting_requests, 0)
      started = System.monotonic_time(:millisecond)
      busy = request(:post, "/v1/extractions", payload("naruto-3"), [{"prefer", "wait=5"}])
      assert busy.status == 202
      assert System.monotonic_time(:millisecond) - started < 2_000
    end
  end

  describe "webhook endpoints API" do
    test "creates with a one-time secret, lists and deletes only the company's endpoints" do
      created =
        request(:post, "/v1/webhook-endpoints", %{
          "appId" => "konoha",
          "url" => "http://localhost:4100/hooks"
        })

      assert created.status == 201
      %{"id" => id, "secret" => "whsec_" <> _ = secret} = Jason.decode!(created.resp_body)
      assert secret == Webhooks.secret(id)

      listed = Jason.decode!(request(:get, "/v1/webhook-endpoints?appId=konoha").resp_body)
      assert [%{"id" => ^id, "url" => "http://localhost:4100/hooks"} = endpoint] = listed["data"]
      refute Map.has_key?(endpoint, "secret")

      assert request(:get, "/v1/webhook-endpoints?appId=akatsuki").resp_body |> Jason.decode!() ==
               %{"data" => []}

      assert request(:delete, "/v1/webhook-endpoints/#{id}?appId=akatsuki").status == 404
      assert request(:delete, "/v1/webhook-endpoints/#{id}?appId=konoha").status == 204
      assert Webhooks.list_endpoints("konoha") == []
    end

    test "requires https when configured and refuses URLs with credentials" do
      Application.put_env(:document_ocr, :webhook_require_https, true)

      for url <- [
            "http://konoha.example/hooks",
            "https://user:pass@konoha.example/hooks",
            "not a url"
          ] do
        assert request(:post, "/v1/webhook-endpoints", %{"appId" => "konoha", "url" => url}).status ==
                 422
      end

      assert request(:post, "/v1/webhook-endpoints", %{
               "appId" => "konoha",
               "url" => "https://konoha.example/hooks"
             }).status == 201
    end
  end

  describe "webhook deliveries" do
    setup do
      {:ok, endpoint, secret} = Webhooks.create_endpoint("konoha", "http://localhost:4100/hooks")
      {:ok, _other, _} = Webhooks.create_endpoint("akatsuki", "http://localhost:4200/hooks")
      %{endpoint: endpoint, secret: secret}
    end

    defp finished_delivery do
      request(:post, "/v1/extractions", payload())
      drain()
      Repo.one!(Delivery)
    end

    test "a finished extraction writes one delivery per company endpoint, without personal data",
         %{endpoint: endpoint} do
      delivery = finished_delivery()
      assert delivery.endpoint_id == endpoint.id
      assert delivery.status == "pending"

      assert %{"type" => "extraction.completed", "data" => %{"status" => "completed"}} =
               delivery.payload

      assert delivery.payload["id"] == delivery.id
      refute inspect(delivery.payload) =~ "NARUTO"
      assert [_] = all_enqueued(worker: DeliverWebhook, args: %{"delivery_id" => delivery.id})
    end

    test "delivery signs the body and marks it delivered on 2xx", %{secret: secret} do
      delivery = finished_delivery()
      parent = self()

      Application.put_env(:document_ocr, :webhook_req_options,
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(parent, {:webhook, conn.req_headers, body})
          Plug.Conn.send_resp(conn, 204, "")
        end
      )

      assert :ok = perform_job(DeliverWebhook, %{"delivery_id" => delivery.id})
      assert_received {:webhook, headers, body}
      headers = Map.new(headers)
      assert headers["aike-event-id"] == delivery.id
      assert headers["aike-event-type"] == "extraction.completed"
      "t=" <> rest = headers["aike-signature"]
      [timestamp, _] = String.split(rest, ",v1=")

      assert headers["aike-signature"] ==
               Webhooks.signature(secret, String.to_integer(timestamp), body)

      assert %{"id" => _, "version" => "v1", "occurredAt" => _, "data" => %{"runId" => _}} =
               Jason.decode!(body)

      delivered = Repo.get!(Delivery, delivery.id)

      assert {delivered.status, delivered.last_status_code, delivered.attempts} ==
               {"delivered", 204, 1}
    end

    test "a failed answer is retried, and the last attempt marks it failed" do
      delivery = finished_delivery()

      Application.put_env(:document_ocr, :webhook_req_options,
        plug: &Plug.Conn.send_resp(&1, 500, "")
      )

      assert {:error, _} =
               perform_job(DeliverWebhook, %{"delivery_id" => delivery.id}, attempt: 1)

      assert %{status: "pending", attempts: 1, last_status_code: 500} =
               Repo.get!(Delivery, delivery.id)

      assert {:error, _} =
               perform_job(DeliverWebhook, %{"delivery_id" => delivery.id}, attempt: 12)

      assert %{status: "failed", attempts: 12} = Repo.get!(Delivery, delivery.id)
    end

    test "deliveries of a deleted endpoint stop", %{endpoint: endpoint} do
      delivery = finished_delivery()
      {:ok, _} = Webhooks.delete_endpoint("konoha", endpoint.id)
      assert {:cancel, _} = perform_job(DeliverWebhook, %{"delivery_id" => delivery.id})
    end
  end

  test "private and unresolvable targets are refused when private targets are not allowed" do
    Application.put_env(:document_ocr, :webhook_allow_private_targets, false)

    for url <- [
          "http://127.0.0.1/hooks",
          "http://169.254.169.254/latest",
          "http://10.0.0.5/",
          "http://[::1]/"
        ] do
      assert {:error, :forbidden_target} = Target.check(url)
    end

    assert {:error, :unresolved_target} = Target.check("http://konoha.invalid/hooks")
    assert :ok = Target.check("http://8.8.8.8/hooks")
  end
end
