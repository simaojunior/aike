defmodule BackofficeWeb.Parsers do
  @moduledoc """
  Body parser plug of the backoffice API.

  It delegates to `AikeHttp.Parsers`.
  """
  defdelegate init(opts), to: AikeHttp.Parsers
  defdelegate call(conn, opts), to: AikeHttp.Parsers
end
