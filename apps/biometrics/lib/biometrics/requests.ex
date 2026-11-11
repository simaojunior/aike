defmodule Biometrics.Requests do
  @moduledoc "Persists replay bindings in the same transaction as the resource and its job."
  alias AikeStorage.Transaction
  alias Biometrics.Requests.Request

  @spec run(module(), atom(), String.t(), term(), String.t(), (-> term()), (String.t() -> term())) ::
          term()
  def run(repo, service, company, key, fingerprint, create, load)
  def run(_repo, _service, _company, nil, _fingerprint, create, _load), do: create.()

  def run(repo, service, company, key, fingerprint, create, load)
      when is_binary(key) and byte_size(key) in 1..256 do
    Transaction.run(repo, {:request, service, company, key}, fn ->
      existing = repo.get_by(Request, service: service, company_id: company, key: key)

      resolve(existing, fingerprint, create, load, repo, %{
        service: service,
        company_id: company,
        key: key
      })
    end)
  end

  def run(_, _, _, _, _, _, _), do: {:error, :invalid_request}

  defp resolve(
         %{fingerprint: fingerprint} = request,
         fingerprint,
         _create,
         load,
         _repo,
         _identity
       ),
       do: load.(request.facematch_session_id)

  defp resolve(%Request{}, _, _, _, _, _), do: {:error, :idempotency_conflict}

  defp resolve(nil, fingerprint, create, _load, repo, identity) do
    with {:ok, value} <- create.(),
         {:ok, _} <-
           repo.insert(struct!(Request, Map.merge(identity, binding(value, fingerprint)))) do
      {:ok, value}
    end
  end

  defp binding(%{session: value}, fingerprint),
    do: %{facematch_session_id: value.id, fingerprint: fingerprint}
end
