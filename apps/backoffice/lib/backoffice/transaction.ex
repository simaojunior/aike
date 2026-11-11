defmodule Backoffice.Transaction do
  @moduledoc "Transactions for domain pipelines with tagged results."
  alias Backoffice.Repo
  @spec run((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}
  def run(fun), do: Repo.transaction(fn -> unwrap(fun.()) end)
  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}), do: Repo.rollback(reason)
end
