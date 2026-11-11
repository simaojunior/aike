defmodule AikeHttp.Envelope do
  @moduledoc """
  The response envelope shared by every processing API (classification, extraction,
  facematch).

  Keys keep a fixed order and are camelCased:

    - `id`: the resource or request ID
    - `version`: the response contract version, `"v1"`
    - `status`, `runId`, `error`: only for asynchronous resources
    - `data`: one entry per document recognized; empty when nothing was recognized or the
      work is not finished
    - `metadata`: `filesInfo` (one entry per file sent) and `processingTimeMs`

  ## Examples

      AikeHttp.Envelope.wrap(
        id: id,
        data: [%{classification: %{type: "drivers_license"}}],
        metadata: %{files_info: [], processing_time_ms: 812}
      )
  """
  alias KycCore.JsonKeyFormatter

  @version "v1"
  @order [:id, :version, :status, :run_id, :error, :data, :metadata]

  @doc """
  Builds an ordered response body.

  ## Parameters
    - fields: keyword list with `:id`, `:data`, `:metadata` and, for asynchronous
      resources, `:status`, `:run_id` and `:error`; snake_case keys at any depth

  ## Returns
    - a `Jason.OrderedObject` ready for `Phoenix.Controller.json/2`
  """
  @spec wrap(keyword()) :: Jason.OrderedObject.t()
  def wrap(fields) do
    fields = Keyword.put_new(fields, :version, @version)

    @order
    |> Enum.filter(&Keyword.has_key?(fields, &1))
    |> Enum.map(&{&1, fields[&1]})
    |> object()
  end

  @doc """
  Builds an ordered JSON object for a nested part of a response.

  ## Parameters
    - fields: keyword list in the output order; snake_case keys at any depth

  ## Returns
    - a `Jason.OrderedObject` with camelCased keys

  ## Example

      AikeHttp.Envelope.object(type: "id_card", side: "front_and_back")
  """
  @spec object(keyword()) :: Jason.OrderedObject.t()
  def object(fields) do
    fields
    |> Enum.map(fn {key, value} ->
      {JsonKeyFormatter.to_camel_case(key), JsonKeyFormatter.format(value)}
    end)
    |> Jason.OrderedObject.new()
  end
end
