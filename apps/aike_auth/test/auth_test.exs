defmodule AikeAuth.TestAdapter do
  def authenticate(_, _), do: Process.get(:identity_result)
end

defmodule AikeAuth.AuthTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  setup do
    old = Application.get_all_env(:aike_auth)
    Application.put_env(:aike_auth, :adapter, AikeAuth.TestAdapter)
    Application.put_env(:aike_auth, :service_account_auth_required, true)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:aike_auth),
          do: Application.delete_env(:aike_auth, key)

      for {key, value} <- old, do: Application.put_env(:aike_auth, key, value)
    end)
  end

  defp request(credentials \\ "ApiKey account:secret") do
    conn(:post, "/")
    |> put_req_header("authorization", credentials)
    |> AikeAuth.Plug.call(app: :aike_auth, scopes: ["ocr:write"])
  end

  test "only a validated identity provides tenant and scopes" do
    Process.put(
      :identity_result,
      {:ok,
       %{
         account_id: "account",
         company_id: "tenant",
         scopes: ["ocr:write"],
         secret: "must-not-propagate"
       }}
    )

    result = request()
    refute result.halted
    assert result.assigns.company_id == "tenant"
    refute Map.has_key?(result.assigns.service_account, :secret)

    Process.put(
      :identity_result,
      {:ok, %{account_id: "other", company_id: "tenant", scopes: ["ocr:write"]}}
    )

    assert request().status == 503
  end

  test "malformed credentials, denial, missing scopes and outages are distinct" do
    assert request("Bearer secret").status == 401
    assert request("ApiKey :secret").status == 401
    Process.put(:identity_result, {:error, :unauthorized})
    assert request().status == 401

    Process.put(
      :identity_result,
      {:ok, %{account_id: "account", company_id: "tenant", scopes: ["ocr:read"]}}
    )

    assert request().status == 403
    Process.put(:identity_result, {:error, :unavailable})
    assert request().status == 503
    Process.put(:identity_result, {:ok, %{account_id: "account", company_id: "", scopes: []}})
    assert request().status == 503
  end

  test "HTTP transport sends credentials only to configured endpoint and never follows redirects" do
    Application.delete_env(:aike_auth, :adapter)
    Application.put_env(:aike_auth, :token, "internal-secret")

    {url, task} =
      server(
        200,
        Jason.encode!(%{accountId: "account", companyId: "tenant", scopes: ["ocr:write"]})
      )

    Application.put_env(:aike_auth, :url, url)
    assert {:ok, %{company_id: "tenant"}} = AikeAuth.authenticate("account", "service-secret")
    request = Task.await(task)
    assert String.downcase(request) =~ "authorization: bearer internal-secret"
    assert request =~ ~s("secret":"service-secret")
    assert request =~ ~s("accountId":"account")

    {url, task} = server(302, "", "location: http://127.0.0.1:1/leak\r\n")
    Application.put_env(:aike_auth, :url, url)
    assert {:error, :unavailable} = AikeAuth.authenticate("account", "secret")
    Task.await(task)
  end

  test "remote cleartext and URL credentials are rejected" do
    refute AikeAuth.HTTP.valid_url?("http://backoffice.internal/introspect")
    refute AikeAuth.HTTP.valid_url?("https://user:secret@backoffice.internal/introspect")
    assert AikeAuth.HTTP.valid_url?("https://backoffice.internal/introspect")
    assert AikeAuth.HTTP.valid_url?("http://127.0.0.1:4003/introspect")
    refute AikeAuth.HTTP.valid_url?("ftp://backoffice.internal/introspect")

    Application.put_env(:aike_auth, :allow_http, true)

    try do
      assert AikeAuth.HTTP.valid_url?("http://backoffice:4000/introspect")
      refute AikeAuth.HTTP.valid_url?("http://user:secret@backoffice:4000/introspect")
    after
      Application.delete_env(:aike_auth, :allow_http)
    end

    Application.put_env(:aike_auth, :url, "http://127.0.0.1:1/introspect")
    Application.put_env(:aike_auth, :token, "internal-secret")
    assert {:error, :unavailable} = AikeAuth.HTTP.authenticate("account", "secret")
  end

  defp server(status, body, headers \\ "") do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listener, 3_000)
          request = receive_request(socket, "")

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 #{status} Test\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n#{headers}\r\n#{body}"
            )

          :gen_tcp.close(socket)
          request
        after
          :gen_tcp.close(listener)
        end
      end)

    {"http://127.0.0.1:#{port}/introspect", task}
  end

  defp receive_request(socket, buffer) do
    case String.split(buffer, "\r\n\r\n", parts: 2) do
      [header, body] ->
        [_, size] = Regex.run(~r/content-length: (\d+)/i, header)

        if byte_size(body) >= String.to_integer(size),
          do: buffer,
          else: receive_more(socket, buffer)

      _ ->
        receive_more(socket, buffer)
    end
  end

  defp receive_more(socket, buffer) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 3_000)
    receive_request(socket, buffer <> chunk)
  end

  test "missing internal token is diagnosed without exposing service credentials" do
    Application.put_env(
      :aike_auth,
      :url,
      "http://localhost:4003/internal/v1/service-accounts/introspect"
    )

    Application.delete_env(:aike_auth, :token)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :unavailable} =
                 AikeAuth.HTTP.authenticate("private-account", "private-secret")
      end)

    assert log =~ "missing_aike_auth_token"
    refute log =~ "private-account"
    refute log =~ "private-secret"
  end

  test "the introspection answer is read in camelCase" do
    body = Jason.encode!(%{accountId: "svc_konoha", companyId: "konoha", scopes: ["ocr:write"]})

    assert AikeAuth.HTTP.identity(body) ==
             {:ok, %{account_id: "svc_konoha", company_id: "konoha", scopes: ["ocr:write"]}}

    snake = Jason.encode!(%{account_id: "svc_konoha", company_id: "konoha", scopes: []})
    assert AikeAuth.HTTP.identity(snake) == :error
  end
end
