defmodule DocumentClassifierWeb.FallbackController do
  @moduledoc "Maps processing failures to the existing HTTP error contract."
  use DocumentClassifierWeb, :controller

  def call(conn, {:error, _step, _reason, _changes}), do: call(conn, {:error, :invalid_request})

  def call(conn, {:error, :overloaded}) do
    conn
    |> put_resp_header("retry-after", DocumentClassifierWeb.ShedLoad.retry_after())
    |> AikeHttp.Problem.send(503, "service_unavailable")
  end

  def call(conn, {:error, reason}) when is_atom(reason) do
    {status, code} = KycCore.HttpErrors.info(reason)
    AikeHttp.Problem.send(conn, status, code)
  end
end
