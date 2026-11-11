defmodule AikeObservability do
  @moduledoc "Shared, privacy-preserving observability helpers."

  @redacted "[REDACTED]"
  @sensitive_keys ~w(
    authorization
    access_token
    birth_date
    cpf
    full_name
    image_bytes
    password
    raw_ocr
    secret
    secret_hash
    token
  )

  @doc "Classifies an HTTP status for structured request logging."
  @spec status_class(non_neg_integer()) :: :success | :client_error | :server_error
  def status_class(status) when status >= 500, do: :server_error
  def status_class(status) when status >= 400, do: :client_error
  def status_class(_status), do: :success

  @doc "Recursively redacts known sensitive map fields before logging."
  @spec redact(term()) :: term()
  def redact(data) when is_map(data) do
    Map.new(data, fn {key, value} ->
      if sensitive_key?(key), do: {key, @redacted}, else: {key, redact(value)}
    end)
  end

  def redact(data) when is_list(data), do: Enum.map(data, &redact/1)
  def redact(data), do: data

  @doc "Returns the Logger level associated with an HTTP status class."
  @spec log_level(non_neg_integer()) :: :info | :warning | :error
  def log_level(status) when status >= 500, do: :error
  def log_level(status) when status >= 400, do: :warning
  def log_level(_status), do: :info

  defp sensitive_key?(key) when is_atom(key), do: key |> Atom.to_string() |> sensitive_key?()
  defp sensitive_key?(key) when is_binary(key), do: String.downcase(key) in @sensitive_keys
  defp sensitive_key?(_key), do: false
end
