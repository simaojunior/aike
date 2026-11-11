defmodule DocumentOcrWeb.WebhookEndpointJSON do
  @moduledoc """
  JSON representations of webhook endpoints.

  ## Examples

      %{id: _, url: "https://konoha.example/hooks", secret: "whsec_" <> _} =
        DocumentOcrWeb.WebhookEndpointJSON.created(endpoint, secret)
  """

  @doc """
  An endpoint just created, with its signing secret. The secret is shown only here.

  ## Parameters
    - endpoint: the new endpoint
    - secret: its signing secret

  ## Returns
    - the map rendered as JSON
  """
  @spec created(map(), String.t()) :: map()
  def created(endpoint, secret), do: endpoint |> data() |> Map.put(:secret, secret)

  @doc """
  The endpoints of a company.

  ## Parameters
    - endpoints: the active endpoints

  ## Returns
    - `%{data: [endpoint]}`
  """
  @spec index([map()]) :: map()
  def index(endpoints), do: %{data: Enum.map(endpoints, &data/1)}

  defp data(endpoint),
    do: %{id: endpoint.id, url: endpoint.url, created_at: endpoint.inserted_at}
end
