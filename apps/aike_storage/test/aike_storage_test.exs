defmodule AikeStorageTest do
  use ExUnit.Case, async: true

  alias AikeStorage.{Adapter.Fake, Blob}

  test "fake adapter stores bytes using the deterministic key" do
    bytes = "fake-image"
    sha = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    assert {:ok, "kyc_documents/" <> ^sha <> ".jpg"} =
             Fake.put(bytes, folder: "kyc_documents", sha256: sha, extension: "jpg")

    assert {:ok, ^bytes} = Fake.get("kyc_documents/#{sha}.jpg")
  end

  test "blob changeset requires metadata" do
    changeset = Blob.changeset(%Blob{}, %{})
    refute changeset.valid?
    assert errors = Keyword.keys(changeset.errors)
    assert :key in errors
    assert :sha256 in errors
  end

  test "fake adapter deletes stored bytes" do
    bytes = "deletable"
    sha = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    key = "kyc_documents/#{sha}.jpg"

    assert {:ok, ^key} = Fake.put(bytes, folder: "kyc_documents", sha256: sha, extension: "jpg")
    assert :ok = Fake.delete(key)
    assert {:error, :not_found} = Fake.get(key)
  end
end
