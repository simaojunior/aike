defmodule Biometrics do
  def compare(selfie, document, opts \\ []) do
    Application.fetch_env!(:biometrics, :engine).compare(selfie, document, opts)
  end
end
