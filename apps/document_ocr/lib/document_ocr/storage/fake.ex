defmodule DocumentOcr.Storage.Fake do
  @moduledoc """
  Fake image storage for tests.

  It returns the same bytes for every key.
  """
  @behaviour DocumentOcr.Storage
  @impl true
  def get(_key), do: {:ok, "fake-image-data"}
end
