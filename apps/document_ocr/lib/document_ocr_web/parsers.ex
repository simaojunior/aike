defmodule DocumentOcrWeb.Parsers do
  @moduledoc """
  Body parser plug of the OCR API.

  It delegates to `AikeHttp.Parsers`.
  """
  defdelegate init(opts), to: AikeHttp.Parsers
  defdelegate call(conn, opts), to: AikeHttp.Parsers
end
