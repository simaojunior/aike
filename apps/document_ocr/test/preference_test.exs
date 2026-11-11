defmodule DocumentOcrWeb.PreferenceTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn
  alias DocumentOcrWeb.Preference

  defp wait(headers) do
    conn = Enum.reduce(headers, conn(:post, "/"), &put_req_header(&2, "prefer", &1))
    Preference.wait(conn)
  end

  test "reads wait, caps it and ignores other preferences" do
    assert wait(["wait=5"]) == 5
    assert wait(["respond-async, wait=3"]) == 3
    assert wait(["Wait=600"]) == 10
  end

  test "no header, respond-async alone or an invalid wait means no wait" do
    for headers <- [[], ["respond-async"], ["wait=0"], ["wait=-1"], ["wait=soon"]] do
      assert wait(headers) == nil
    end
  end
end
