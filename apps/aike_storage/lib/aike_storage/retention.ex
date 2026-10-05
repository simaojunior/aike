defmodule AikeStorage.Retention do
  @moduledoc "Pure retention policy for stored blobs."

  @spec expired?(AikeStorage.Blob.t(), DateTime.t(), non_neg_integer()) :: boolean()
  def expired?(blob, now \\ DateTime.utc_now(), seconds)

  def expired?(%AikeStorage.Blob{inserted_at: inserted_at}, now, seconds)
      when is_integer(seconds) and seconds >= 0 do
    DateTime.diff(now, inserted_at, :second) >= seconds
  end

  def expired?(_, _, _), do: false
end
