defmodule DocumentOcr.ExternalCallTest do
  use ExUnit.Case, async: true

  test "returns the adapter result" do
    assert {:ok, :done} = DocumentOcr.ExternalCall.run(fn -> {:ok, :done} end, 100)
  end

  test "returns timeout and terminates the task" do
    parent = self()

    assert {:error, :timeout} =
             DocumentOcr.ExternalCall.run(
               fn ->
                 Process.sleep(100)
                 send(parent, :finished)
               end,
               1
             )

    refute_receive :finished, 150
  end
end
