defmodule AikeStorage.LocalTest do
  use ExUnit.Case, async: false
  alias AikeStorage.Adapter.Local

  setup do
    previous = Application.fetch_env!(:aike_storage, :local_root)
    root = Path.join(System.tmp_dir!(), "aike-local-#{System.unique_integer([:positive])}")
    Application.put_env(:aike_storage, :local_root, root)

    on_exit(fn ->
      Application.put_env(:aike_storage, :local_root, previous)
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  defp options(bytes),
    do: [sha256: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower), extension: "jpg"]

  test "bytes survive the uploading process and are stored privately", %{root: root} do
    bytes = <<0, 255, 10, 1, 2>>
    {:ok, key} = Task.async(fn -> Local.put(bytes, options(bytes)) end) |> Task.await()
    assert {:ok, ^bytes} = Local.get(key)
    assert {:ok, ^key} = Local.put(bytes, options(bytes))
    assert {:ok, stat} = File.stat(Path.join(root, key))
    assert Bitwise.band(stat.mode, 0o777) == 0o600
    assert Path.wildcard(Path.join(root, "**/*.tmp")) == []
    assert :ok = Local.delete(key)
    assert :ok = Local.delete(key)
    assert {:error, :not_found} = Local.get(key)
  end

  test "keys cannot escape the upload directory", %{root: root} do
    for key <- ["../secret", "/tmp/secret", "folder/../../secret", "folder/%2e%2e/secret", nil] do
      assert {:error, :invalid_key} = Local.get(key)
      assert {:error, :invalid_key} = Local.delete(key)
    end

    assert {:error, :invalid_key} = Local.put("x", options("x") ++ [folder: "../escape"])
    refute File.exists?(root)
  end

  test "checksum mismatch and filesystem failures are explicit and sanitized", %{root: root} do
    assert {:error, :invalid_checksum} = Local.put("changed", options("original"))
    File.write!(root, "directory-is-a-file")
    assert {:error, :storage_unavailable} = Local.put("bytes", options("bytes"))
  end
end
