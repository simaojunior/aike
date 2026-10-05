defmodule DocumentOcr.Documents.Processor do
  alias DocumentOcr.Repo
  alias DocumentOcr.Documents.DocumentStatus

  def start_processing(document), do: transition(document, "processing")
  def complete(document), do: transition(document, "completed", nil, nil, "approved")

  def require_confirmation(document, reason),
    do:
      transition(
        document,
        "requires_confirmation",
        "requires_confirmation",
        reason,
        "manual_review"
      )

  def reject(document),
    do: transition(document, "rejected", "invalid_fields", "Field validation failed", "rejected")

  def fail(document, code, message), do: transition(document, "failed", code, message, nil)

  def cancel(document),
    do: transition(document, "failed", "cancelled", "Processing cancelled by client")

  @doc false
  def restart(document, profile, request_id) do
    DocumentOcr.Documents.with_current_run(document, fn current ->
      attrs =
        Map.take(profile, [
          :pipeline_version,
          :ocr_engine,
          :ocr_engine_version,
          :extractor_version
        ])
        |> Map.merge(%{
          run_id: Ecto.UUID.generate(),
          status: "pending",
          request_id: request_id,
          error_code: nil,
          error_message: nil,
          decision: nil
        })

      current |> Ecto.Changeset.change(attrs) |> Repo.update()
    end)
  end

  defp transition(document, status, code \\ nil, message \\ nil, decision \\ nil) do
    DocumentOcr.Documents.with_current_run(document, fn document ->
      allowed =
        (document.status == "pending" and status == "processing") or
          (document.status == "processing" and status != "pending") or
          (document.status == "pending" and status == "failed") or document.status == status

      if allowed and DocumentStatus.valid?(status),
        do: :ok,
        else: Repo.rollback(:invalid_transition)

      document
      |> Ecto.Changeset.change(
        status: status,
        decision: decision,
        error_code: code,
        error_message: message
      )
      |> Repo.update()
    end)
  end
end
