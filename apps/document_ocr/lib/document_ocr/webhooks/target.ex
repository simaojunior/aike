defmodule DocumentOcr.Webhooks.Target do
  @moduledoc """
  Decides whether a webhook URL may be called, to stop server-side request forgery.

  The host is resolved at delivery time and refused when any address is loopback,
  private, link-local (cloud metadata), unique-local, multicast or unspecified. Development
  and tests allow private targets so local receivers work.

  ## Configuration

      config :document_ocr, webhook_allow_private_targets: false

  ## Examples

      :ok = DocumentOcr.Webhooks.Target.check("https://konoha.example/hooks")
      {:error, :forbidden_target} = DocumentOcr.Webhooks.Target.check("https://169.254.169.254/")
  """

  @doc """
  Checks a webhook URL before a delivery.

  ## Parameters
    - url: the endpoint URL

  ## Returns
    - `:ok`
    - `{:error, :forbidden_target}` for a private address
    - `{:error, :unresolved_target}` when the host does not resolve
  """
  @spec check(String.t()) :: :ok | {:error, :forbidden_target | :unresolved_target}
  def check(url) do
    check(
      URI.parse(url).host,
      Application.get_env(:document_ocr, :webhook_allow_private_targets, false)
    )
  end

  defp check(_host, true), do: :ok

  defp check(host, false) when is_binary(host) do
    host
    |> addresses()
    |> verdict()
  end

  defp check(_host, false), do: {:error, :unresolved_target}

  defp addresses(host) do
    charlist = String.to_charlist(host)

    for family <- [:inet, :inet6],
        {:ok, found} <- [:inet.getaddrs(charlist, family)],
        address <- found,
        do: address
  end

  defp verdict([]), do: {:error, :unresolved_target}

  defp verdict(addresses) do
    if_private(Enum.any?(addresses, &private?/1))
  end

  defp if_private(true), do: {:error, :forbidden_target}
  defp if_private(false), do: :ok

  defp private?({127, _, _, _}), do: true
  defp private?({10, _, _, _}), do: true
  defp private?({172, second, _, _}) when second in 16..31, do: true
  defp private?({192, 168, _, _}), do: true
  defp private?({169, 254, _, _}), do: true
  defp private?({100, second, _, _}) when second in 64..127, do: true
  defp private?({0, _, _, _}), do: true
  defp private?({first, _, _, _}) when first >= 224, do: true
  defp private?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp private?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private?({0, 0, 0, 0, 0, 65_535, high, low}), do: private?(ipv4(high, low))
  defp private?({first, _, _, _, _, _, _, _}) when first in 0xFC00..0xFDFF, do: true
  defp private?({first, _, _, _, _, _, _, _}) when first in 0xFE80..0xFEBF, do: true
  defp private?({first, _, _, _, _, _, _, _}) when first in 0xFF00..0xFFFF, do: true
  defp private?(_address), do: false

  defp ipv4(high, low), do: {div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)}
end
