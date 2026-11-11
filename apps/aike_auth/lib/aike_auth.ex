defmodule AikeAuth do
  @moduledoc "Service identity boundary; processing services never read administrative tables."
  @callback authenticate(String.t(), String.t()) ::
              {:ok, map()} | {:error, :unauthorized | :unavailable}

  @doc "Validated identity for the credentials; cached briefly, see `AikeAuth.Cache`."
  def authenticate(account_id, secret),
    do: AikeAuth.Cache.fetch(account_id, secret, fn -> introspect(account_id, secret) end)

  defp introspect(account_id, secret) do
    adapter = Application.get_env(:aike_auth, :adapter, AikeAuth.HTTP)

    case adapter.authenticate(account_id, secret) do
      {:ok, %{account_id: ^account_id, company_id: company, scopes: scopes} = identity}
      when is_binary(company) and byte_size(company) > 0 and is_list(scopes) ->
        if Enum.all?(scopes, &is_binary/1),
          do: {:ok, Map.take(identity, [:account_id, :company_id, :scopes])},
          else: {:error, :unavailable}

      {:error, :unauthorized} ->
        {:error, :unauthorized}

      _ ->
        {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end
end
