defmodule AikeHttp.FieldIssues do
  @moduledoc "Safe field/detail projection of Peri errors. Raw content is never serialized."
  def from_peri(%Peri.Error{} = error), do: from_peri([error])

  def from_peri(errors) when is_list(errors) do
    errors |> Enum.flat_map(&peri_detail/1) |> Enum.uniq() |> Enum.sort_by(&{&1.field, &1.detail})
  end

  defp peri_detail(%Peri.Error{errors: errors}) when is_list(errors),
    do: Enum.flat_map(errors, &peri_detail/1)

  defp peri_detail(%Peri.Error{} = error) do
    {_code, message} = peri_description(error)
    field = Enum.map_join(error.path || [], ".", &to_string/1)
    [%{field: field, detail: message}]
  end

  # Peri messages/content may contain the rejected value. Only allow safe metadata.
  defp peri_description(%{content: %{code: code} = content}), do: coded_description(code, content)

  defp peri_description(%{content: %{expected: _} = content}) do
    if Map.has_key?(content, :actual),
      do: {"invalid_type", "This field has an invalid type."},
      else: {"required", "This field is required."}
  end

  defp peri_description(%{content: %{type: _}}),
    do: {"invalid_type", "This field has an invalid type."}

  defp peri_description(%{content: %{regex: _}}),
    do: {"invalid_format", "This field has an invalid format."}

  defp peri_description(%{content: %{length: length}, message: message}) do
    if String.starts_with?(message, "should have the minimum"),
      do: {"too_short", "Must contain at least #{length} characters."},
      else: {"too_long", "Must contain at most #{length} characters."}
  end

  defp peri_description(_), do: {"invalid_value", "This field has an invalid value."}

  defp coded_description("required" = code, _), do: {code, "This field is required."}
  defp coded_description("invalid_type" = code, _), do: {code, "This field has an invalid type."}

  defp coded_description("invalid_format" = code, _),
    do: {code, "This field has an invalid format."}

  defp coded_description("too_short" = code, content),
    do: {code, "Must contain at least #{content.count} characters."}

  defp coded_description("invalid_idempotency_key" = code, _),
    do: {code, "Provide one Idempotency-Key header containing 1 to 256 bytes."}

  defp coded_description("invalid_upload" = code, _),
    do: {code, "Must be a multipart file upload."}

  defp coded_description("invalid_base64" = code, _),
    do: {code, "Must be a non-empty base64-encoded document."}

  defp coded_description("invalid_images" = code, _),
    do: {code, "Provide one or two images with distinct sides."}

  defp coded_description("too_many_bytes", _), do: {"too_long", "Must contain at most 1024 bytes."}
  defp coded_description(_, _), do: {"invalid_value", "This field has an invalid value."}
end
