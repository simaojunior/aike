defmodule KycCore.HttpErrors do
  @moduledoc "Documented processing API error codes; unknown domain errors are rejected."
  @errors %{
    idempotency_conflict: {409, "idempotency_conflict"},
    invalid_request: {422, "invalid_request"},
    invalid_upload: {422, "invalid_request"},
    unsupported_image: {415, "unsupported_file"},
    image_too_large: {422, "image_too_large"},
    unsupported_page_count: {422, "unsupported_page_count"},
    file_too_large: {413, "file_too_large"},
    service_unavailable: {503, "service_unavailable"},
    overloaded: {503, "service_unavailable"},
    storage_unavailable: {503, "service_unavailable"},
    invalid_processing_configuration: {503, "service_unavailable"},
    not_found: {404, "not_found"},
    document_not_found: {404, "not_found"},
    invalid_pipeline_version: {422, "invalid_pipeline_version"},
    unsupported_pipeline_version: {422, "invalid_pipeline_version"},
    not_cancellable: {409, "document_not_cancellable"}
  }
  @spec info(atom()) :: {integer(), String.t()}
  def info(reason), do: Map.fetch!(@errors, reason)
end
