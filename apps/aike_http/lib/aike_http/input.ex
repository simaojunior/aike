defmodule AikeHttp.Input do
  @moduledoc "Peri custom rules for API uploads. No file or database access."
  def upload(%Plug.Upload{path: path, filename: name}) when is_binary(path) and is_binary(name),
    do: :ok

  def upload(_), do: {:error, "Expected multipart upload.", code: "invalid_upload"}

  def base64(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, bytes} when byte_size(bytes) > 0 -> :ok
      _ -> {:error, "Invalid base64.", code: "invalid_base64"}
    end
  end

  def base64(_), do: {:error, "Expected base64 string.", code: "invalid_type"}

  def uuid(value) when is_binary(value) do
    if Regex.match?(~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i, value),
      do: :ok,
      else: {:error, "Invalid UUID.", code: "invalid_format"}
  end

  def uuid(_), do: {:error, "Invalid type.", code: "invalid_type"}

  def idempotency_key(value) when is_binary(value) and byte_size(value) in 1..256, do: :ok

  def idempotency_key(_),
    do: {:error, "Invalid idempotency key.", code: "invalid_idempotency_key"}
end
