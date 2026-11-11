defmodule AikeAuth.HTTP do
  @moduledoc "Bounded HTTP introspection with TLS verification and no redirects. `AikeAuth.Cache` caches its valid answers."
  @behaviour AikeAuth
  require Logger

  @impl true
  def authenticate(account_id, secret) do
    url = Application.get_env(:aike_auth, :url)
    token = Application.get_env(:aike_auth, :token)

    with :ok <- validate_configuration(url, token) do
      request = {
        String.to_charlist(url),
        [{~c"authorization", String.to_charlist("Bearer " <> token)}],
        ~c"application/json",
        Jason.encode!(%{accountId: account_id, secret: secret})
      }

      :httpc.request(:post, request, http_options(), body_format: :binary)
      |> decode()
    else
      {:error, reason} -> unavailable(reason)
    end
  rescue
    _ -> unavailable(:unexpected_exception)
  end

  defp validate_configuration(url, token) do
    cond do
      not valid_url?(url) -> {:error, :invalid_backoffice_auth_url}
      not (is_binary(token) and byte_size(token) > 0) -> {:error, :missing_aike_auth_token}
      true -> :ok
    end
  end

  defp unavailable(reason) do
    Logger.error("Service identity introspection failed: #{reason}",
      event: "auth.introspection.failed"
    )

    {:error, :unavailable}
  end

  defp http_options do
    [
      timeout: 3_000,
      connect_timeout: 1_000,
      autoredirect: false,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]
  end

  @doc """
  Tells whether a backoffice introspection URL is acceptable.

  HTTPS is always accepted. Plain HTTP is accepted on loopback, and on any host only when
  `config :aike_auth, allow_http: true` (`AIKE_AUTH_ALLOW_HTTP=true`). The request carries
  the credential secret, so plain HTTP is only for a private network between the services.

  ## Parameters
    - url: the configured URL

  ## Returns
    - `true` or `false`; URLs with credentials or a fragment are refused
  """
  @spec valid_url?(term()) :: boolean()
  def valid_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, userinfo: nil, fragment: nil}
      when is_binary(host) and host != "" ->
        allowed_scheme?(scheme, host)

      _ ->
        false
    end
  end

  def valid_url?(_), do: false

  defp allowed_scheme?("https", _host), do: true

  defp allowed_scheme?("http", host),
    do:
      host in ["localhost", "127.0.0.1", "::1"] or
        Application.get_env(:aike_auth, :allow_http, false)

  defp allowed_scheme?(_scheme, _host), do: false

  defp decode({:ok, {{_, 200, _}, _, body}}) when byte_size(body) <= 16_384 do
    case identity(body) do
      {:ok, identity} -> {:ok, identity}
      :error -> unavailable(:invalid_identity_response)
    end
  end

  defp decode({:ok, {{_, 401, _}, _, _}}), do: {:error, :unauthorized}
  defp decode({:error, _}), do: unavailable(:connection_failed)

  defp decode({:ok, {{_, status, _}, _, _}}) when is_integer(status),
    do: unavailable("unexpected_http_status_#{status}")

  defp decode(_), do: unavailable(:invalid_http_response)

  @doc """
  Reads the identity from the backoffice introspection answer (camelCase JSON).

  ## Parameters
    - body: the response body

  ## Returns
    - `{:ok, %{account_id, company_id, scopes}}`
    - `:error` for any other shape
  """
  @spec identity(binary()) :: {:ok, map()} | :error
  def identity(body) do
    case Jason.decode(body) do
      {:ok, %{"accountId" => account, "companyId" => company, "scopes" => scopes}} ->
        {:ok, %{account_id: account, company_id: company, scopes: scopes}}

      _ ->
        :error
    end
  end
end
