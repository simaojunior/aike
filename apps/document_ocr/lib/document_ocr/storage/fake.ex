defmodule DocumentOcr.Storage.Fake do
  @behaviour DocumentOcr.Storage
  @impl true
  def get(_key), do: {:ok, "fake-image-data"}
end
