defmodule DocumentOcr.ProvisioningBoundaryTest do
  use ExUnit.Case, async: true

  test "OCR no longer owns administrative endpoints" do
    paths = Enum.map(DocumentOcrWeb.Router.__routes__(), & &1.path)
    refute "/v1/companies" in paths
    refute "/v1/service-accounts" in paths
  end
end
