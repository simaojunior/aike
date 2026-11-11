defmodule AikeHttp.Prefer do
  @moduledoc """
  Reads the `prefer` request header (RFC 7240) of asynchronous resources.

  `wait=N` asks the server to answer within N seconds with the finished resource when
  possible. The wait is capped by the service. `respond-async` alone, an invalid value or
  no header means no wait.

  ## Examples

      conn = Plug.Conn.put_req_header(conn, "prefer", "wait=10")
      10 = AikeHttp.Prefer.wait(conn, 10)
  """

  @doc """
  Seconds the client is willing to wait, capped by `max_seconds`.

  ## Parameters
    - conn: the request
    - max_seconds: the longest wait the service allows

  ## Returns
    - the seconds to wait, or `nil` when the client asked for no wait
  """
  @spec wait(Plug.Conn.t(), pos_integer()) :: pos_integer() | nil
  def wait(conn, max_seconds) do
    conn
    |> Plug.Conn.get_req_header("prefer")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.find_value(&seconds/1)
    |> cap(max_seconds)
  end

  defp seconds("wait=" <> value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds > 0 -> seconds
      _ -> nil
    end
  end

  defp seconds(_preference), do: nil

  defp cap(nil, _max), do: nil
  defp cap(seconds, max), do: min(seconds, max)
end
