defmodule DocumentOcrWeb.ValidateParams do
  @moduledoc """
  Parameter validation plug of the OCR API.

  It delegates to `AikeHttp.ValidateParams`.
  """
  defdelegate init(opts), to: AikeHttp.ValidateParams
  defdelegate call(conn, opts), to: AikeHttp.ValidateParams
end
