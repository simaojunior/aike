defmodule AikeStorage.RetentionTest do
  use ExUnit.Case, async: true

  test "identifies blobs past the configured retention" do
    inserted = ~U[2026-01-01 00:00:00Z]
    blob = %AikeStorage.Blob{inserted_at: inserted}
    assert AikeStorage.Retention.expired?(blob, ~U[2026-01-31 00:00:00Z], 30 * 24 * 60 * 60)
    refute AikeStorage.Retention.expired?(blob, ~U[2026-01-10 00:00:00Z], 30 * 24 * 60 * 60)
  end
end
