defmodule BackofficeWeb.Schemas.InputRules do
  @moduledoc "Custom Peri rules for byte limits, password policy and UUID syntax."

  alias Backoffice.Accounts.Password

  def new_password(value) do
    case Password.validation_error(value) do
      nil ->
        :ok

      {_message, opts} ->
        code =
          case {opts[:validation], opts[:kind]} do
            {:required, _} -> "required"
            {:cast, _} -> "invalid_type"
            {:length, :min} -> "too_short"
            {:byte_length, _} -> "too_many_bytes"
            _ -> "invalid_format"
          end

        {:error, "Invalid password.", code: code, count: opts[:count]}
    end
  end

  def credential(value) when is_binary(value) do
    cond do
      byte_size(value) == 0 -> {:error, "Required credential.", code: "required"}
      byte_size(value) > 1024 -> {:error, "Credential is too long.", code: "too_many_bytes"}
      true -> :ok
    end
  end

  def credential(_), do: {:error, "Invalid type.", code: "invalid_type"}

  defdelegate uuid(value), to: AikeHttp.Input
end
