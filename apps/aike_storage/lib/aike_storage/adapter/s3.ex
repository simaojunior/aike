defmodule AikeStorage.Adapter.S3 do
  @moduledoc """
  Private object storage on any S3-compatible service.

  Cloudflare R2 or Amazon S3 in production, SeaweedFS locally. Requests use path-style URLs
  and AWS Signature V4 (`Req`). Keys are content-addressed
  (`<folder>/<sha256>.<extension>`), so writing the same bytes twice is harmless. Requests
  do not retry: the processing pipeline owns retries and timeouts.

  ## Configuration

      config :aike_storage,
        adapter: AikeStorage.Adapter.S3,
        s3: [
          endpoint: "https://<account>.r2.cloudflarestorage.com",
          bucket: "aike-documents",
          region: "auto",
          access_key_id: "...",
          secret_access_key: "..."
        ]

  In production the values come from `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION`,
  `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY`.

  ## Errors
    - `:invalid_checksum`: the bytes do not match the given SHA-256
    - `:invalid_key`: the key is outside the managed format; no request is sent
    - `:not_found`: the object does not exist
    - `:storage_unavailable`: the service failed or did not answer

  ## Examples

      {:ok, key} = AikeStorage.Adapter.S3.put(bytes, sha256: sha256, extension: "jpg")
      {:ok, ^bytes} = AikeStorage.Adapter.S3.get(key)
      :ok = AikeStorage.Adapter.S3.delete(key)
  """
  @behaviour AikeStorage.Adapter

  @key ~r/\A[a-zA-Z0-9_-]+\/[a-f0-9]{64}\.[a-zA-Z0-9]{1,16}\z/

  @doc """
  Stores `data` under its content-addressed key.

  ## Parameters
    - data: the file bytes
    - opts: `:sha256` (required, checked against `data`), `:extension` (required),
      `:folder` (default `"kyc_documents"`)

  ## Returns
    - `{:ok, key}`
    - `{:error, :invalid_checksum | :invalid_key | :storage_unavailable}`
  """
  @impl true
  def put(data, opts) when is_binary(data) do
    sha256 = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

    key =
      "#{Keyword.get(opts, :folder, "kyc_documents")}/#{sha256}.#{Keyword.fetch!(opts, :extension)}"

    with true <- sha256 == Keyword.fetch!(opts, :sha256) || {:error, :invalid_checksum},
         {:ok, url} <- url(key),
         {:ok, %Req.Response{status: status}} when status in 200..299 <-
           request(:put, url, body: data, headers: [{"content-type", "application/octet-stream"}]) do
      {:ok, key}
    else
      {:error, :invalid_checksum} = error -> error
      {:error, :invalid_key} = error -> error
      _ -> {:error, :storage_unavailable}
    end
  end

  @doc """
  Reads an object.

  ## Parameters
    - key: a key returned by `put/2`

  ## Returns
    - `{:ok, data}`
    - `{:error, :not_found | :invalid_key | :storage_unavailable}`
  """
  @impl true
  def get(key) do
    with {:ok, url} <- url(key) do
      case request(:get, url) do
        {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
        {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
        _ -> {:error, :storage_unavailable}
      end
    end
  end

  @doc """
  Deletes an object. Deleting a missing object succeeds.

  ## Parameters
    - key: a key returned by `put/2`

  ## Returns
    - `:ok`
    - `{:error, :invalid_key | :storage_unavailable}`
  """
  @impl true
  def delete(key) do
    with {:ok, url} <- url(key) do
      case request(:delete, url) do
        {:ok, %Req.Response{status: status}} when status in [200, 204, 404] -> :ok
        _ -> {:error, :storage_unavailable}
      end
    end
  end

  @doc """
  Lists the managed objects of the bucket, following pagination.

  Used by `AikeStorage.Reconciliation` to remove orphans left by a crash between upload
  and database commit. The result has the shape of `AikeStorage.LocalInventory.list/1`.

  ## Parameters
    - folder: the owner's folder; only keys under it are listed

  ## Returns
    - `{:ok, objects}`: each with `key`, `hash`, `modified` (Unix time) and `temporary`
    - `{:error, :storage_unavailable}`
  """
  @spec list(String.t()) :: {:ok, [map()]} | {:error, :storage_unavailable}
  def list(folder), do: list_page(folder, nil, [])

  defp list_page(folder, token, objects) do
    config = config()
    query = continuation([{"list-type", "2"}, {"prefix", folder <> "/"}], token)

    url =
      "#{String.trim_trailing(config[:endpoint], "/")}/#{config[:bucket]}?#{URI.encode_query(query)}"

    with {:ok, %Req.Response{status: 200, body: body}} <- request(:get, url),
         {:ok, page, next} <- parse_listing(body, folder) do
      next_page(folder, next, objects ++ page)
    else
      _ -> {:error, :storage_unavailable}
    end
  end

  defp parse_listing(body, folder) do
    pattern = ~r/\A#{Regex.escape(folder)}\/([a-f0-9]{64})\.[a-zA-Z0-9]{1,16}\z/

    {document, _} = :xmerl_scan.string(String.to_charlist(body), quiet: true)

    objects =
      for content <- :xmerl_xpath.string(~c"//*[local-name()='Contents']", document),
          key = text(content, "Key"),
          [_, hash] <- [Regex.run(pattern, key)],
          {:ok, modified, _} <- [DateTime.from_iso8601(text(content, "LastModified"))],
          do: %{key: key, hash: hash, modified: DateTime.to_unix(modified), temporary: false}

    {:ok, objects, next_token(text(document, "IsTruncated"), document)}
  rescue
    _ -> {:error, :invalid_listing}
  catch
    :exit, _ -> {:error, :invalid_listing}
  end

  defp text(node, name) do
    case :xmerl_xpath.string(~c"./*[local-name()='#{name}']/text()", node) ++
           :xmerl_xpath.string(~c"//*[local-name()='#{name}']/text()", node) do
      [{:xmlText, _, _, _, value, _} | _] -> to_string(value)
      _ -> ""
    end
  end

  defp continuation(query, nil), do: query
  defp continuation(query, token), do: query ++ [{"continuation-token", token}]

  defp next_page(_folder, nil, objects), do: {:ok, objects}
  defp next_page(folder, token, objects), do: list_page(folder, token, objects)

  defp next_token("true", document), do: text(document, "NextContinuationToken")
  defp next_token(_truncated, _document), do: nil

  defp url(key) when is_binary(key), do: managed_url(Regex.match?(@key, key), key)

  defp url(_), do: {:error, :invalid_key}

  defp managed_url(false, _key), do: {:error, :invalid_key}

  defp managed_url(true, key) do
    config = config()
    {:ok, "#{String.trim_trailing(config[:endpoint], "/")}/#{config[:bucket]}/#{key}"}
  end

  defp request(method, url, opts \\ []) do
    config = config()

    Req.request(
      [
        method: method,
        url: url,
        retry: false,
        decode_body: false,
        receive_timeout: 5_000,
        connect_options: [timeout: 2_000],
        aws_sigv4: [
          service: :s3,
          region: config[:region],
          access_key_id: config[:access_key_id],
          secret_access_key: config[:secret_access_key]
        ]
      ] ++ opts ++ Keyword.get(config, :req_options, [])
    )
  rescue
    _ -> {:error, :storage_unavailable}
  end

  defp config, do: Application.fetch_env!(:aike_storage, :s3)
end
