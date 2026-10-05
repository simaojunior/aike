defmodule DocumentOcr.ProcessingConfig do
  @moduledoc "Captures trusted processing provenance and resolves explicitly registered adapters."
  @fields [:pipeline_version, :ocr_engine, :ocr_engine_version, :extractor_version]

  def capture(version)
      when is_binary(version) and byte_size(version) > 0 and byte_size(version) <= 128 do
    with {:ok, profile} <- capture() do
      if profile.pipeline_version == version,
        do: {:ok, profile},
        else: {:error, :unsupported_pipeline_version}
    end
  end

  def capture(_), do: {:error, :invalid_pipeline_version}

  def capture do
    config = Application.get_all_env(:document_ocr)
    module = config[:ocr_engine]

    profile = %{
      pipeline_version: config[:pipeline_version],
      ocr_engine: if(is_atom(module) and not is_nil(module), do: inspect(module)),
      ocr_engine_version: config[:ocr_engine_version],
      extractor_version: config[:extractor_version]
    }

    with {:ok, profile} <- metadata(profile),
         {:ok, _} <- engine(profile, config),
         {:ok, _} <- extractor("cnh", profile.extractor_version, config) do
      {:ok, profile}
    else
      _ -> {:error, :invalid_processing_configuration}
    end
  end

  def metadata(document) do
    profile = Map.take(document, @fields)

    if Enum.all?(@fields, &non_empty?(profile[&1])) do
      {:ok, profile}
    else
      {:error, :missing_processing_configuration}
    end
  end

  def engine(profile, config \\ Application.get_all_env(:document_ocr)) do
    # Never create atoms from persisted strings, and never fall back to the active engine.
    registered = Keyword.get(config, :ocr_engines, [])

    module =
      Enum.find_value(registered, fn {module, version} ->
        if inspect(module) == profile.ocr_engine and version == profile.ocr_engine_version,
          do: module
      end)

    if callable?(module, :extract, 2), do: {:ok, module}, else: {:error, :ocr_engine_unavailable}
  end

  def extractor(type, version, config \\ Application.get_all_env(:document_ocr)) do
    module = config |> Keyword.get(:extractors, %{}) |> Map.get({type, version})
    if callable?(module, :extract, 1), do: {:ok, module}, else: {:error, :extractor_unavailable}
  end

  defp non_empty?(value), do: is_binary(value) and String.trim(value) != ""

  defp callable?(module, function, arity) do
    is_atom(module) and not is_nil(module) and Code.ensure_loaded?(module) and
      function_exported?(module, function, arity)
  end
end
