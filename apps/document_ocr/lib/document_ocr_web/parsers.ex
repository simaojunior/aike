defmodule DocumentOcrWeb.Parsers do
  defdelegate init(opts), to: AikeHttp.Parsers
  defdelegate call(conn, opts), to: AikeHttp.Parsers
end
