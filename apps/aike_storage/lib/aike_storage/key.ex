defmodule AikeStorage.Key do
  def for(binary, filename, opts \\ []) when is_binary(binary) do
    sha256 = :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
    extension = extension(filename, Keyword.get(opts, :mime_type))
    folder = Keyword.get(opts, :folder, "kyc_documents")
    {sha256, "#{folder}/#{sha256}.#{extension}", extension}
  end

  defp extension(filename, _mime_type) when is_binary(filename) do
    case Path.extname(filename) |> String.trim_leading(".") |> String.downcase() do
      "" -> "bin"
      value -> value
    end
  end

  defp extension(_, "image/jpeg"), do: "jpg"
  defp extension(_, "image/png"), do: "png"
  defp extension(_, _), do: "bin"
end
