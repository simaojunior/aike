defmodule DocumentClassifier.ConcurrentClassificationTest do
  use ExUnit.Case, async: true

  test "concurrent identical requests succeed independently without a repository" do
    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          DocumentClassifier.Classifications.classify(
            %{"image" => Base.encode64("fake:cnh_front")},
            "tenant"
          )
        end)
      end

    assert [{:ok, first}, {:ok, second}] = Enum.map(tasks, &Task.await/1)
    assert first == second
    refute Code.ensure_loaded?(DocumentClassifier.Repo)
  end
end
