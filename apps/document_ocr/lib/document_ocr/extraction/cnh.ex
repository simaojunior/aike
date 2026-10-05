defmodule DocumentOcr.Extraction.CNH do
  def extract(%{"text" => [name, cpf, birth | _]}) do
    with {:ok, name} <- field(name, &Function.identity/1),
         {:ok, cpf} <- field(cpf, &String.replace(&1, ~r/[.\-\s]/, "")),
         {:ok, birth} <- field(birth, &normalize_date/1) do
      {:ok,
       %{
         "document" => %{"type" => "cnh", "country" => "BR"},
         "person" => %{"full_name" => name, "cpf" => cpf, "birth_date" => birth}
       }}
    end
  end

  def extract(_), do: {:error, :invalid_ocr_output}

  defp field(%{"text" => text, "confidence" => confidence}, normalize)
       when is_binary(text) and is_number(confidence) and confidence >= 0 and confidence <= 1 do
    {:ok,
     %{
       "value" => normalize.(text),
       "raw_value" => text,
       "confidence" => confidence,
       "status" => "accepted"
     }}
  end

  defp field(_, _), do: {:error, :invalid_ocr_output}

  defp normalize_date(text) do
    case Regex.run(~r/^(\d{2})\/(\d{2})\/(\d{4})$/, text) do
      [_, day, month, year] -> "#{year}-#{month}-#{day}"
      _ -> text
    end
  end
end
