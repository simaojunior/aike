defmodule DocumentClassifier.Identifier do
  @moduledoc false
  def generate do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)
    hex = Base.encode16(<<a::48, 4::4, b::12, 2::2, c::62>>, case: :lower)

    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary>> =
      hex

    Enum.join([a, b, c, d, e], "-")
  end
end
