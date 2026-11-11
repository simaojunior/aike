defmodule DocumentOcr.Webhooks.Endpoint do
  @moduledoc """
  A company's URL that receives extraction events.

  The signing secret is not stored: it is derived from the server key and the endpoint ID
  (see `DocumentOcr.Webhooks.secret/1`). Production accepts only `https` URLs; any
  environment rejects URLs with credentials or longer than 2048 characters.

  ## Fields
    - `id`: endpoint ID (UUID)
    - `company_id`: the owning company, from the authenticated service account
    - `url`: where events are sent
    - `active`: deleted endpoints stay as inactive rows, so pending deliveries stop
  """
  use DocumentOcr, :model

  @type t :: %__MODULE__{}

  schema "webhook_endpoints" do
    field(:company_id, :string)
    field(:url, :string)
    field(:active, :boolean, default: true)
    timestamps()
  end

  @doc """
  Builds a changeset for a new endpoint.

  ## Parameters
    - endpoint: an empty endpoint
    - attrs: `:company_id` and `:url`

  ## Returns
    - a changeset; invalid when the URL is not accepted
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:company_id, :url])
    |> validate_required([:company_id, :url])
    |> validate_length(:url, max: 2048)
    |> validate_change(:url, fn :url, url -> url_errors(URI.parse(url)) end)
  end

  defp url_errors(%URI{scheme: scheme, host: host, userinfo: nil})
       when is_binary(host) and host != "" do
    scheme_errors(scheme, host, Application.get_env(:document_ocr, :webhook_require_https, true))
  end

  defp url_errors(_uri), do: [url: "must be an absolute URL without credentials"]

  defp scheme_errors("https", _host, _require_https), do: []
  defp scheme_errors("http", _host, false), do: []
  defp scheme_errors(_scheme, _host, _require_https), do: [url: "must use https"]
end
