defmodule BackofficeWeb.EnsureAuthenticated do
  @moduledoc "Rejects anonymous protected requests before body parsing."
  import Plug.Conn

  def init(opts), do: opts

  def call(%{method: "POST", request_path: path} = conn, _)
      when path in ["/v1/auth/bootstrap", "/v1/auth/login", "/v1/auth/refresh"], do: conn

  def call(%{assigns: %{identity: _}} = conn, _), do: conn

  def call(conn, _),
    do: conn |> BackofficeWeb.FallbackController.call({:error, :unauthorized}) |> halt()
end
