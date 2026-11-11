defmodule AikeStorage.S3AdapterTest do
  use ExUnit.Case, async: false
  alias AikeStorage.Adapter.S3

  @data "document-bytes"
  @sha256 :crypto.hash(:sha256, @data) |> Base.encode16(case: :lower)
  @key "kyc_documents/#{@sha256}.jpg"

  setup do
    previous = Application.get_env(:aike_storage, :s3)

    Application.put_env(:aike_storage, :s3,
      endpoint: "http://storage.test/",
      bucket: "bucket",
      region: "auto",
      access_key_id: "key-id",
      secret_access_key: "key-secret",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.put_env(:aike_storage, :s3, previous) end)
  end

  defp respond(status, body \\ "") do
    parent = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, request_body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, conn.method, conn.request_path, request_body, conn.req_headers})
      Plug.Conn.send_resp(conn, status, body)
    end)
  end

  test "put signs a path-style request with a content-addressed key" do
    respond(200)
    assert {:ok, @key} = S3.put(@data, sha256: @sha256, extension: "jpg")
    assert_received {:request, "PUT", "/bucket/" <> @key, @data, headers}

    assert {"authorization", "AWS4-HMAC-SHA256 " <> credential} =
             List.keyfind(headers, "authorization", 0)

    assert credential =~ "Credential=key-id/"
    refute inspect(headers) =~ "key-secret"
  end

  test "put refuses bytes that do not match the checksum, without a request" do
    respond(200)

    assert {:error, :invalid_checksum} =
             S3.put(@data, sha256: String.duplicate("0", 64), extension: "jpg")

    refute_received {:request, _, _, _, _}
  end

  test "get maps found, missing and failing objects" do
    respond(200, @data)
    assert {:ok, @data} = S3.get(@key)
    respond(404)
    assert {:error, :not_found} = S3.get(@key)
    respond(500)
    assert {:error, :storage_unavailable} = S3.get(@key)
  end

  test "delete is idempotent and reports failures" do
    for status <- [204, 404] do
      respond(status)
      assert :ok = S3.delete(@key)
    end

    respond(503)
    assert {:error, :storage_unavailable} = S3.delete(@key)
  end

  test "transport errors are storage unavailability" do
    Req.Test.stub(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))
    assert {:error, :storage_unavailable} = S3.get(@key)
  end

  defp listing(keys, next) do
    contents =
      Enum.map_join(keys, fn key ->
        "<Contents><Key>#{key}</Key><LastModified>2026-10-01T10:00:00.000Z</LastModified></Contents>"
      end)

    truncated =
      if next,
        do:
          "<IsTruncated>true</IsTruncated><NextContinuationToken>#{next}</NextContinuationToken>",
        else: "<IsTruncated>false</IsTruncated>"

    ~s(<?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">) <>
      truncated <> contents <> "</ListBucketResult>"
  end

  test "list follows continuation tokens and keeps only managed objects" do
    second = "kyc_documents/#{String.duplicate("b", 64)}.pdf"

    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["prefix"] == "kyc_documents/"

      body =
        case conn.query_params["continuation-token"] do
          nil ->
            listing(
              [
                @key,
                "kyc_documents/not-managed.txt",
                "facematch/#{String.duplicate("c", 64)}.jpg"
              ],
              "page-2"
            )

          "page-2" ->
            listing([second], nil)
        end

      Plug.Conn.send_resp(conn, 200, body)
    end)

    assert {:ok, [first, last]} = S3.list("kyc_documents")
    assert %{key: @key, hash: @sha256, temporary: false, modified: modified} = first
    assert modified == DateTime.to_unix(~U[2026-10-01 10:00:00Z])
    assert last.key == second
  end

  test "an unreadable listing is storage unavailability" do
    respond(200, "not xml")
    assert {:error, :storage_unavailable} = S3.list("kyc_documents")
    respond(403)
    assert {:error, :storage_unavailable} = S3.list("kyc_documents")
  end

  test "keys outside the managed format never reach the network" do
    respond(200)

    for key <- ["../secret", "kyc_documents/abc.jpg", nil, "a/#{@sha256}.jpg/../x"] do
      assert {:error, :invalid_key} = S3.get(key)
    end

    refute_received {:request, _, _, _, _}
  end
end
